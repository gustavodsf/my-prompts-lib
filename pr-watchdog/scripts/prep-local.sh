#!/usr/bin/env bash
# prep-local.sh [base]
# Builds a review bundle from the LOCAL working tree — no PR required. Same bundle shape as
# prep.sh, so the five lanes and the reconciler need no changes.
#
# Why a snapshot commit and not the working tree directly: lanes must all review the same
# bytes. If they read the live tree while you keep typing, they review different code and the
# agreement percentage stops meaning anything.
#
# The snapshot is built through a TEMPORARY INDEX so it includes untracked files.
# `git stash create` does not, and that is not a detail: on the branch this was written
# against, 11 of 50 changed paths were untracked and they contained the entire new module.
# A snapshot without them reviews the change with its subject missing.
#
# Nothing is written to the working tree, the index, or the stash list.
set -euo pipefail

# Target resolution, in order: --worktree, then the CURRENT directory's worktree, then
# WATCHDOG_REPO. It must default to cwd, not to a configured path: with several tickets in
# flight as separate worktrees, a fixed default silently reviews the wrong branch's work.
# Measured on this machine: Delivery-API-TECH-5766 is a worktree of Delivery-API carrying 84
# dirty paths on a different ticket.
TARGET=""
BASE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree|-w) TARGET="${2:?--worktree needs a path}"; shift 2 ;;
    --base|-b)     BASE_ARG="${2:?--base needs a ref}"; shift 2 ;;
    --list|-l)
      echo "worktrees available:" >&2
      git -C "${WATCHDOG_REPO:-$HOME/dev/Delivery-API}" worktree list >&2 2>/dev/null
      exit 0 ;;
    -*) echo "prep-local.sh: unknown flag $1" >&2; exit 2 ;;
    *)  BASE_ARG="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -n "$TARGET" ] || TARGET="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"

REPO="$TARGET"
WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
BASE="${BASE_ARG:-${WATCHDOG_BASE:-test}}"
SKILLDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Sibling-first, which is correct in both installs: the two skills sit next to each other
# whether that is ~/.claude/skills/ or a repo's .claude/skills/. Falls back to the home
# install so an engineer running the repo copy without one still resolves.
if [ -n "${WATCHDOG_REVIEW_SKILL:-}" ]; then
  REVIEW_SKILL="$WATCHDOG_REVIEW_SKILL"
elif [ -d "$SKILLDIR/../watchdog-review" ]; then
  REVIEW_SKILL="$(cd "$SKILLDIR/../watchdog-review" && pwd)"
else
  REVIEW_SKILL="$HOME/.claude/skills/watchdog-review"
fi

die() { echo "prep-local.sh: $*" >&2; exit 1; }
. "$(dirname "${BASH_SOURCE[0]}")/_exclusions.sh"

cd "$REPO" 2>/dev/null || die "cannot enter $REPO"
git rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git repository or worktree"

# Refuse to review a watchdog worktree -- those are throwaway checkouts the watchdog itself
# creates, and reviewing one reviews a snapshot of a snapshot.
case "$REPO" in
  "$WS"/worktrees/*) die "$REPO is a watchdog worktree, not your work. cd to your checkout." ;;
esac
git fetch -q origin "$BASE" || die "cannot fetch origin/$BASE"

BRANCH=$(git branch --show-current 2>/dev/null || echo "DETACHED")
echo "prep-local.sh: reviewing $REPO on branch $BRANCH" >&2
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
UNTRACKED=$(git status --porcelain | grep -c '^??' || true)

# Snapshot tracked modifications AND untracked files, without touching anything.
TMPIDX=$(mktemp -t wd-idx); rm -f "$TMPIDX"
export GIT_INDEX_FILE="$TMPIDX"
git read-tree HEAD
git add -A 2>/dev/null || true
TREE=$(git write-tree)
unset GIT_INDEX_FILE
rm -f "$TMPIDX"
SHA=$(git commit-tree "$TREE" -p HEAD -m "watchdog local snapshot of $BRANCH")
SHORT=${SHA:0:12}

MB=$(git merge-base "origin/$BASE" "$SHA")
# Keyed on the worktree, not just the branch: two worktrees can sit on the same branch, and
# the branch name alone does not tell a reader which checkout was reviewed.
SLUG=$(basename "$REPO")-$(echo "$BRANCH" | tr '/' '-')
OUT="$WS/reviews/LOCAL-$SLUG/$SHORT"
mkdir -p "$OUT"
rm -f "$OUT"/lane-*.md "$OUT/summary.md" "$OUT/detail.md" "$OUT/format.md" "$OUT/ticket.md" \
      "$OUT/previous-summary.md" "$OUT/blame.txt" "$OUT/prior-prs.json" \
      "$OUT/file-history.txt" "$OUT/checks.txt"
rm -rf "$OUT/review"

# Full counts for the record, then the reviewed diff with generated output excluded.
FULL_LINES=$(git diff "$MB..$SHA" | wc -l | tr -d ' ')
FULL_FILES=$(git diff "$MB..$SHA" --name-only | wc -l | tr -d ' ')
git diff "$MB..$SHA" -- . "${EXCLUDE_PATHSPEC[@]}" > "$OUT/diff.patch"
git diff "$MB..$SHA" --name-status -- . "${EXCLUDE_PATHSPEC[@]}" > "$OUT/files.txt"
git diff "$MB..$SHA" --name-only -- . > "$OUT/files-all.txt"
comm -13 <(awk '{print $2}' "$OUT/files.txt" | sort) <(sort "$OUT/files-all.txt") \
  > "$OUT/files-excluded.txt" || true
git log --oneline "$MB..$SHA" > "$OUT/commits.txt"
[ -s "$OUT/files.txt" ] || die "nothing to review: no difference between origin/$BASE and your working tree"

# The snapshot commit is not on any branch, so a worktree at it is a clean read-only copy of
# exactly what is being reviewed -- including your uncommitted work.
WT="$WS/worktrees/local-$SLUG"
git worktree remove --force "$WT" 2>/dev/null || true
git worktree add -q --detach "$WT" "$SHA"

# No PR, so no CI. Say so plainly rather than leaving lanes to guess.
echo "no PR yet - CI has not run on this code" > "$OUT/checks.txt"
jq -n --arg b "$BRANCH" --argjson dirty "$DIRTY" --argjson untracked "${UNTRACKED:-0}" \
  '{number:null, title:("LOCAL: " + $b), body:null,
    author:{login:"local"}, headRefName:$b,
    localSnapshot:true, dirtyPaths:$dirty, untrackedPaths:$untracked}' > "$OUT/pr.json"

# Conventions from the base branch, never the working tree -- so edits in progress to the
# rules do not grade themselves.
rm -rf "$OUT/checklist"; mkdir -p "$OUT/checklist"
snap() { git show "origin/$BASE:$1" > "$OUT/checklist/$2" 2>/dev/null || true; }
snap .claude/skills/review/SKILL.md              repo-review-skill.md
snap .claude/skills/shared/security-checklist.md security-checklist.md
snap .claude/skills/shared/common-rules.md       common-rules.md
snap specs/standards/coding-standards.md         coding-standards.md
snap specs/standards/review-checklist.md         review-checklist.md
snap specs/standards/observability-standards.md  observability-standards.md
for r in $(git ls-tree --name-only "origin/$BASE:.claude/rules" 2>/dev/null); do
  snap ".claude/rules/$r" "rule-$r"
done
find "$OUT/checklist" -size 0 -delete

[ -d "$REVIEW_SKILL" ] || die "review standard not found at $REVIEW_SKILL"
cp -R "$REVIEW_SKILL" "$OUT/review"

# The reconciler is told to follow an output format; give it a real path to one. Keeping the
# templates in a file rather than in SKILL.md also stops SKILL.md growing every time the
# output changes. (Brendan Glancy)
[ -f "$SKILLDIR/output-format.md" ] || die "output-format.md missing from $SKILLDIR"
cp "$SKILLDIR/output-format.md" "$OUT/format.md"

TICKET=$(printf '%s' "$BRANCH" | grep -oE 'TECH-[0-9]+' | head -1 || true)

jq -n --arg branch "$BRANCH" --arg sha "$SHA" --arg short "$SHORT" --arg wt "$WT" \
      --arg out "$OUT" --arg mb "$MB" --arg base "$BASE" --arg ticket "$TICKET" \
      --arg url "${TICKET:+https://app.clickup.com/t/9010032869/$TICKET}" \
      --argjson lines "$(wc -l < "$OUT/diff.patch")" \
      --argjson files "$(wc -l < "$OUT/files.txt")" \
      --argjson fullLines "${FULL_LINES:-0}" --argjson fullFiles "${FULL_FILES:-0}" \
      --argjson excluded "$(wc -l < "$OUT/files-excluded.txt" | tr -d ' ')" \
      --argjson dirty "$DIRTY" --argjson untracked "${UNTRACKED:-0}" \
      --arg repo "$REPO" \
  '{mode:"local", pr:null, branch:$branch, worktreePath:$repo, sha:$sha, short:$short, worktree:$wt,
    outDir:$out, mergeBase:$mb, base:$base, diffLines:$lines, changedFiles:$files,
    fullDiffLines:$fullLines, fullChangedFiles:$fullFiles, excludedFiles:$excluded,
    dirtyPaths:$dirty, untrackedPathsIncluded:$untracked,
    ticket:$ticket, ticketUrl:$url, previousSha:"", ciAvailable:false}' \
  | tee "$OUT/meta.json"

"$SKILLDIR/scripts/context.sh" "$OUT" > "$OUT/context-stats.json" \
  || echo '{"error":"context gathering failed"}' > "$OUT/context-stats.json"
