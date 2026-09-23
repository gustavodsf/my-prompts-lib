#!/usr/bin/env bash
# context.sh <outDir>
# Pre-computes the historical evidence all five lanes need: blame for the changed hunks,
# prior PRs that touched the same files, and the review comments left on those PRs.
#
# Gathered ONCE, read five times. Each lane still judges the evidence independently -- that
# is where the 5x confidence comes from -- but they do not each re-run the same git and gh
# calls. Same accuracy, a fifth of the fetching.
set -euo pipefail

OUT="${1:?usage: context.sh <outDir>}"
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
BASE="${WATCHDOG_BASE:-test}"
MAX_PRIOR="${WATCHDOG_MAX_PRIOR_PRS:-6}"
# Blame scales with (files x changed lines) and is injected into all five lanes, so it is the
# one input that can silently dwarf the diff. Measured 2026-08-26: PR 3020 (81 files)
# produced 367k chars = ~92k tokens per lane, ~460k across five. Capped, and what gets
# dropped is always stated -- a truncated file that claims to be complete is worse than none.
MAX_BLAME_CHARS="${WATCHDOG_MAX_BLAME_CHARS:-48000}"
MAX_BLAME_LINES_PER_FILE="${WATCHDOG_MAX_BLAME_LINES_PER_FILE:-40}"

MB=$(jq -r '.mergeBase' "$OUT/meta.json")
SHA=$(jq -r '.sha' "$OUT/meta.json")
cd "$REPO"

FILES=$(awk '$1 != "D" {print $2}' "$OUT/files.txt" | grep -vE '\.(lock|snap)$|^$' || true)
# Blame on a test file tells you who wrote the test, which is rarely why a change is wrong.
BLAME_FILES=$(printf '%s\n' $FILES | grep -vE '(__tests__/|\.spec\.|\.test\.|/generated/)' || true)
# Guard FIRST. With FILES empty, `grep -c .` prints 0 *and* exits 1, so `|| echo 0` appends a
# second 0 and the arithmetic below sees "0\n0" -- a syntax error that leaves the variable
# unset for `set -u` to kill on first use. (Brendan Glancy)
[ -n "$FILES" ] || { echo '{"skipped":"no files"}'; exit 0; }
BLAME_SKIPPED_TESTS=$(( $(printf '%s\n' $FILES | grep -c . || echo 0) - $(printf '%s\n' $BLAME_FILES | grep -c . || echo 0) ))

# ---- blame for the pre-image of each changed hunk -------------------------------------
# Who last touched the lines this PR is changing, and in which commit. A bug is often only
# visible against the change that introduced the line.
: > "$OUT/blame.txt"
BLAME_TRUNCATED=0; BLAME_FILES_DONE=0; BLAME_FILES_DROPPED=0
for f in $BLAME_FILES; do
  if [ "$(wc -c < "$OUT/blame.txt" | tr -d ' ')" -ge "$MAX_BLAME_CHARS" ]; then
    BLAME_TRUNCATED=1; BLAME_FILES_DROPPED=$((BLAME_FILES_DROPPED+1)); continue
  fi
  git cat-file -e "$MB:$f" 2>/dev/null || continue          # new file: nothing to blame
  ranges=$(git diff -U0 "$MB..$SHA" -- "$f" \
    | grep -oE '^@@ -[0-9]+(,[0-9]+)?' | sed 's/^@@ -//' || true)
  [ -n "$ranges" ] || continue
  echo "=== $f" >> "$OUT/blame.txt"
  for r in $ranges; do
    start=${r%%,*}; len=${r##*,}
    [ "$len" = "$r" ] && len=1
    [ "$len" -eq 0 ] && continue
    end=$((start + len - 1))
    git blame -L "$start,$end" --date=short -- "$f" "$MB" 2>/dev/null \
      | head -"$MAX_BLAME_LINES_PER_FILE" | sed 's/^/    /' >> "$OUT/blame.txt" || true
  done
  BLAME_FILES_DONE=$((BLAME_FILES_DONE+1))
done

# Say what was left out. Silent truncation reads as "this is all of it".
{
  echo
  echo "=== blame coverage"
  echo "    files blamed: $BLAME_FILES_DONE"
  [ "$BLAME_SKIPPED_TESTS" -gt 0 ] && \
    echo "    skipped as tests/generated: $BLAME_SKIPPED_TESTS (blame on a test says who wrote the test)"
  [ "$BLAME_FILES_DROPPED" -gt 0 ] && \
    echo "    DROPPED for size: $BLAME_FILES_DROPPED files — blame is INCOMPLETE. Run 'git blame' yourself on any file you need."
  echo "    per-file line cap: $MAX_BLAME_LINES_PER_FILE"
} >> "$OUT/blame.txt"

# ---- prior PRs that touched these files, and what reviewers said on them --------------
# Institutional memory: if a reviewer flagged something here before, it probably applies again.
PRS=$(git log --merges --format='%s' "$MB" -- $FILES 2>/dev/null \
  | grep -oE '#[0-9]+' | tr -d '#' | awk '!seen[$0]++' | head -"$MAX_PRIOR" || true)

echo "[]" > "$OUT/prior-prs.json"
if [ -n "$PRS" ]; then
  {
    for n in $PRS; do
      body=$(gh pr view "$n" --json number,title,url,body 2>/dev/null || echo '{}')
      inline=$(gh api "repos/{owner}/{repo}/pulls/$n/comments" --paginate 2>/dev/null \
        | jq '[.[] | {author:.user.login, path, line, body}]' 2>/dev/null || echo '[]')
      reviews=$(gh pr view "$n" --json reviews 2>/dev/null \
        | jq '[(.reviews // [])[] | select((.body // "") != "")
               | {author:.author.login, state, body}]' 2>/dev/null || echo '[]')
      jq -n --argjson pr "$body" --argjson inline "$inline" --argjson reviews "$reviews" \
        '{pr: ($pr.number // null), title: ($pr.title // null), url: ($pr.url // null),
          inlineComments: $inline, reviewBodies: $reviews,
          commentCount: (($inline|length) + ($reviews|length))}'
    done
  } | jq -s '.' > "$OUT/prior-prs.json"
fi

# ---- recent history of the touched files ----------------------------------------------
git log --format='%h%x09%aI%x09%an%x09%s' -25 "$MB" -- $FILES > "$OUT/file-history.txt" 2>/dev/null || true

jq -n \
  --argjson blameLines "$(wc -l < "$OUT/blame.txt" | tr -d ' ')" \
  --argjson priorPrs "$(jq 'length' "$OUT/prior-prs.json")" \
  --argjson priorComments "$(jq '[.[].commentCount] | add // 0' "$OUT/prior-prs.json")" \
  --argjson historyLines "$(wc -l < "$OUT/file-history.txt" | tr -d ' ')" \
  --argjson blameChars "$(wc -c < "$OUT/blame.txt" | tr -d ' ')" \
  --argjson blameFilesDropped "${BLAME_FILES_DROPPED:-0}" \
  --argjson blameTruncated "${BLAME_TRUNCATED:-0}" \
  '{blameLines:$blameLines, blameChars:$blameChars,
    blameFilesDropped:$blameFilesDropped, blameTruncated:($blameTruncated == 1),
    priorPrs:$priorPrs, priorComments:$priorComments, historyLines:$historyLines,
    approxTokensPerLane: (($blameChars + 4000) / 4 | floor)}'
