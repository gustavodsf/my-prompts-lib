#!/usr/bin/env bash
# ground-truth.sh <pr-number> <merge-commit>
# Gathers what actually happened to a merged PR, for scoring a review against reality.
#
# Two labels, in increasing strength:
#   humanFlagged  -- what human reviewers thought worth saying. A recall proxy, not truth:
#                    humans miss things too, so absence here is weak evidence.
#   postMergeFixes -- commits touching the SAME files after the merge whose subject looks
#                    like a fix, revert, or hotfix. This is the strong label: something got
#                    through review and had to be repaired.
set -euo pipefail

PR="${1:?usage: ground-truth.sh <pr-number> <merge-commit>}"
MERGE="${2:?merge commit sha required}"
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
BASE="${WATCHDOG_BASE:-test}"

cd "$REPO"
git fetch -q origin "$BASE"

FILES=$(git diff --name-only "$MERGE^" "$MERGE" 2>/dev/null || true)

# Filter in jq, not grep -- an empty grep exits 1 and pipefail turns that into a hard fail.
FIXES='[]'
if [ -n "$FILES" ]; then
  FIXES=$(git log --format='%H%x09%an%x09%aI%x09%s' "$MERGE..origin/$BASE" -- $FILES 2>/dev/null \
    | jq -Rs 'split("\n") | map(select(length>0)) | map(split("\t")
              | {sha:.[0], author:.[1], at:.[2], subject:.[3]})
              | map(select(.subject | test("fix|hotfix|revert|patch|correct|bug"; "i")))')
  [ -n "$FIXES" ] || FIXES='[]'
fi

REVIEWS=$(gh pr view "$PR" --json reviews,comments 2>/dev/null || echo '{}')
INLINE=$(gh api "repos/{owner}/{repo}/pulls/$PR/comments" --paginate 2>/dev/null \
  | jq '[.[] | {author:.user.login, path, line, body}]' || echo '[]')

jq -n --argjson reviews "$REVIEWS" --argjson inline "$INLINE" --argjson fixes "$FIXES" \
      --arg pr "$PR" --arg merge "$MERGE" \
      --argjson files "$(printf '%s' "$FILES" | jq -Rs 'split("\n")|map(select(length>0))')" '
  {
    pr: $pr, mergeCommit: $merge, changedFiles: $files,
    humanFlagged: {
      reviewBodies: [($reviews.reviews // [])[] | select((.body // "") != "")
                     | {author: .author.login, state, body}],
      inlineComments: $inline,
      count: (([($reviews.reviews // [])[] | select((.body//"") != "")] | length) + ($inline | length))
    },
    postMergeFixes: { commits: $fixes, count: ($fixes | length) }
  }'
