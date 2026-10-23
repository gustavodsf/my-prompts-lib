#!/usr/bin/env bash
# corpus.sh <count>
# Lists MERGED PRs for the backwards calibration corpus, newest first.
#
# Only merged-into-base counts. A closed-unmerged PR was abandoned, and a draft was never
# offered for review -- neither carries a review decision worth learning from, and both
# would teach the reviewer on work nobody accepted.
set -euo pipefail

N="${1:-20}"
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
BASE="${WATCHDOG_BASE:-test}"

cd "$REPO"
gh pr list --state merged --base "$BASE" --limit "$N" \
  --json number,title,headRefName,mergeCommit,mergedAt,author,additions,deletions,reviewDecision,isDraft \
  | jq '
      map(select(.isDraft == false))
      | map(select(.mergedAt != null))
      | map({number, title, branch: .headRefName, author: .author.login,
             mergedAt, mergeCommit: .mergeCommit.oid,
             additions, deletions, reviewDecision,
             ticket: ((.title + " " + .headRefName) | capture("(?<t>TECH-[0-9]+)").t? // null)})
      | sort_by(.mergedAt) | reverse
    '
