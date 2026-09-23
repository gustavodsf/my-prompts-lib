#!/usr/bin/env bash
# prep.sh <pr-number>
# Builds a read-only review bundle for one PR: worktree at the PR head, diff vs
# merge-base with test, changed files, commits, and CI status.
# No npm install -- node_modules is ~1GB; CI is the test/lint signal instead.
set -euo pipefail

SKILLDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PR="${1:?usage: prep.sh <pr-number>}"
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
BASE="${WATCHDOG_BASE:-test}"
# The review standard is its own skill so engineers can run it on their own branch. One
# source: what they run and what the lanes run are the same file.
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

die() { echo "prep.sh: $*" >&2; exit 1; }

# Pin gh to one account, immune to a concurrent `gh auth switch` in another shell.
. "$(dirname "${BASH_SOURCE[0]}")/_gh-account.sh"
. "$(dirname "${BASH_SOURCE[0]}")/_exclusions.sh"

cd "$REPO"
git fetch -q origin "$BASE"
git fetch -q origin "pull/$PR/head:refs/watchdog/pr-$PR" --force

SHA=$(git rev-parse "refs/watchdog/pr-$PR")
SHORT=${SHA:0:12}
WT="$WS/worktrees/pr-$PR"
OUT="$WS/reviews/PR-$PR/$SHORT"
mkdir -p "$OUT"
# Clear every artifact this run rewrites, not just the review output. A run that dies partway
# must not leave last pass's data looking like this pass's.
rm -f "$OUT"/lane-*.md "$OUT/summary.md" "$OUT/ticket.md" "$OUT/previous-summary.md" \
      "$OUT/blame.txt" "$OUT/prior-prs.json" "$OUT/file-history.txt" \
      "$OUT/pr.json" "$OUT/pr.err" "$OUT/checks.json" "$OUT/checks.txt" "$OUT/checks.err" \
      "$OUT/detail.md" "$OUT/format.md"
rm -rf "$OUT/review"

git worktree remove --force "$WT" 2>/dev/null || true
git worktree add -q --detach "$WT" "$SHA"

# Most recent earlier pass on this PR, if any. Goes to the RECONCILER only -- never to a
# lane. Lanes must stay blind or the vote percentage stops meaning "N independent reads".
PREV_SHA=""
PREV=$(find "$WS/reviews/PR-$PR" -mindepth 2 -maxdepth 2 -name summary.md \
        -not -path "*/$SHORT/*" 2>/dev/null | xargs -r ls -t 2>/dev/null | head -1 || true)
if [ -n "$PREV" ]; then
  cp "$PREV" "$OUT/previous-summary.md"
  PREV_SHA=$(basename "$(dirname "$PREV")")
fi

MB=$(git merge-base "origin/$BASE" "$SHA")
# Full counts for the record, then the reviewed diff with generated output excluded.
FULL_LINES=$(git diff "$MB..$SHA" | wc -l | tr -d ' ')
FULL_FILES=$(git diff "$MB..$SHA" --name-only | wc -l | tr -d ' ')
git diff "$MB..$SHA" -- . "${EXCLUDE_PATHSPEC[@]}" > "$OUT/diff.patch"
git diff "$MB..$SHA" --name-status -- . "${EXCLUDE_PATHSPEC[@]}" > "$OUT/files.txt"
git diff "$MB..$SHA" --name-only -- . > "$OUT/files-all.txt"
comm -13 <(awk '{print $2}' "$OUT/files.txt" | sort) <(sort "$OUT/files-all.txt") \
  > "$OUT/files-excluded.txt" || true
git log --oneline "$MB..$SHA" > "$OUT/commits.txt"

# A merged (or already-in-base) PR has merge-base == head, so the diff is empty. Refuse
# rather than hand five lanes an empty bundle to review.
if [ ! -s "$OUT/files.txt" ]; then
  git worktree remove --force "$WT" 2>/dev/null || true
  echo "PR $PR has an empty diff against $BASE (merge-base == head)." >&2
  echo "It is probably already merged. Nothing to review; skipping." >&2
  jq -n --arg pr "$PR" --arg sha "$SHA" \
    '{pr:$pr, sha:$sha, skipped:"empty diff -- already merged into base"}'
  exit 3
fi
# Never let an error message land in a bundle file. A lane reading checks.txt cannot tell
# "auth failed" from "CI is red", and a `{}` pr.json silently empties the ticket lookup, so the
# whole run degrades into confident nonsense. Both fetches fail the script instead.
gh pr view "$PR" --json number,title,body,author,headRefName,labels,additions,deletions,files \
  > "$OUT/pr.json" 2>"$OUT/pr.err" \
  || die "gh pr view $PR failed as '$GH_ACCOUNT': $(head -2 "$OUT/pr.err" | tr '\n' ' ')"
jq -e --arg pr "$PR" '(.number // -1) == ($pr | tonumber)' "$OUT/pr.json" >/dev/null 2>&1 \
  || die "pr.json is not PR $PR -- wrong repo, wrong account, or a truncated response"
rm -f "$OUT/pr.err"

# `gh pr checks` exits 1 when a check failed and 8 when checks are still running. Both are real
# answers about the PR; anything else is a tooling fault and must not be written to the bundle.
set +e
gh pr checks "$PR" --json name,state,link > "$OUT/checks.json" 2>"$OUT/checks.err"
checks_code=$?
set -e
if [ "$checks_code" -ne 0 ] && ! jq -e 'type == "array"' "$OUT/checks.json" >/dev/null 2>&1; then
  if grep -qi "no checks reported" "$OUT/checks.err"; then
    echo '[]' > "$OUT/checks.json"
  else
    die "gh pr checks $PR failed (exit $checks_code) as '$GH_ACCOUNT': $(head -2 "$OUT/checks.err" | tr '\n' ' ')"
  fi
fi
jq -e 'type == "array"' "$OUT/checks.json" >/dev/null 2>&1 \
  || die "checks.json is not a JSON array -- refusing to hand lanes an unreadable CI signal"
# checks.txt is derived from the JSON, so it can only ever hold real rows.
jq -r 'if length == 0 then "no checks reported"
       else .[] | "\(.state)\t\(.name)\t\(.link // "")" end' \
  "$OUT/checks.json" > "$OUT/checks.txt"
rm -f "$OUT/checks.err"

# Checklist comes from the base branch, never the PR head -- otherwise a PR that edits
# the review skill would grade itself against its own rewritten rules.
rm -rf "$OUT/checklist"
mkdir -p "$OUT/checklist"
snap() { git show "origin/$BASE:$1" > "$OUT/checklist/$2" 2>/dev/null || true; }
snap .claude/skills/review/SKILL.md            repo-review-skill.md
snap .claude/skills/shared/security-checklist.md security-checklist.md
snap .claude/skills/shared/common-rules.md     common-rules.md
snap specs/standards/review-checklist.md       review-checklist.md
snap specs/standards/coding-standards.md       coding-standards.md
snap specs/standards/observability-standards.md observability-standards.md
for r in $(git ls-tree --name-only "origin/$BASE:.claude/rules" 2>/dev/null); do
  snap ".claude/rules/$r" "rule-$r"
done
find "$OUT/checklist" -size 0 -delete

# Copied into the bundle so a run always reviews against the version current when it started,
# even if someone edits the skill mid-run.
[ -d "$REVIEW_SKILL" ] || die "review standard not found at $REVIEW_SKILL -- install the watchdog-review skill"
cp -R "$REVIEW_SKILL" "$OUT/review"

# The reconciler is told to follow an output format; give it a real path to one. Keeping the
# templates in a file rather than in SKILL.md also stops SKILL.md growing every time the
# output changes. (Brendan Glancy)
[ -f "$SKILLDIR/output-format.md" ] || die "output-format.md missing from $SKILLDIR"
cp "$SKILLDIR/output-format.md" "$OUT/format.md"

# Ticket ID drives the ClickUp acceptance-criteria fetch. Title first, branch as fallback.
TITLE=$(jq -r '.title // ""' "$OUT/pr.json")
BRANCH=$(jq -r '.headRefName // ""' "$OUT/pr.json")
TICKET=$(printf '%s %s' "$TITLE" "$BRANCH" | grep -oE 'TECH-[0-9]+' | head -1 || true)

# Local spec, if the team wrote one for this ticket. Usually absent -- ClickUp is the real source.
SPEC=""
if [ -n "$TICKET" ]; then
  SPEC=$(git ls-tree --name-only -d "origin/$BASE:specs/features" 2>/dev/null | grep "^${TICKET}-" | head -1 || true)
  if [ -n "$SPEC" ]; then
    mkdir -p "$OUT/spec"
    for f in $(git ls-tree --name-only "origin/$BASE:specs/features/$SPEC"); do
      git show "origin/$BASE:specs/features/$SPEC/$f" > "$OUT/spec/$f" 2>/dev/null || true
    done
  fi
fi

jq -n --arg pr "$PR" --arg sha "$SHA" --arg short "$SHORT" --arg wt "$WT" \
      --arg out "$OUT" --arg mb "$MB" --arg base "$BASE" \
      --argjson lines "$(wc -l < "$OUT/diff.patch")" \
      --argjson files "$(wc -l < "$OUT/files.txt")" \
      --argjson fullLines "${FULL_LINES:-0}" --argjson fullFiles "${FULL_FILES:-0}" \
      --argjson excluded "$(wc -l < "$OUT/files-excluded.txt" | tr -d ' ')" \
      --arg ticket "$TICKET" --arg spec "$SPEC" --arg prev "$PREV_SHA" \
      --arg ghAccount "$GH_ACCOUNT" \
      --arg url "${TICKET:+https://app.clickup.com/t/9010032869/$TICKET}" \
  '{pr:$pr,sha:$sha,short:$short,worktree:$wt,outDir:$out,mergeBase:$mb,base:$base,
    diffLines:$lines,changedFiles:$files,fullDiffLines:$fullLines,fullChangedFiles:$fullFiles,excludedFiles:$excluded,ticket:$ticket,ticketUrl:$url,localSpec:$spec,
    previousSha:$prev, ghAccount:$ghAccount}' \
  | tee "$OUT/meta.json"

# Historical evidence, gathered once for all five lanes (see context.sh header).
# Must run after meta.json exists -- context.sh reads mergeBase and sha from it.
"$SKILLDIR/scripts/context.sh" "$OUT" > "$OUT/context-stats.json" \
  || echo '{"error":"context gathering failed"}' > "$OUT/context-stats.json"
