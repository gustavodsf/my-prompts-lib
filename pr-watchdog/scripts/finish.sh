#!/usr/bin/env bash
# finish.sh <pr-number> <sha>
# Records the reviewed SHA and drops the worktree. Only run after the summary exists.
set -euo pipefail

PR="${1:?usage: finish.sh <pr-number> <sha>}"
SHA="${2:?usage: finish.sh <pr-number> <sha>}"
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
STATE="$WS/state.json"
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq --arg pr "$PR" --arg sha "$SHA" --arg at "$STAMP" \
   '.[$pr] = {sha:$sha, reviewedAt:$at}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

# Record this review's CI signal before the bundle ages out. One PR with skipped gates is
# a footnote; a streak is a broken pipeline, and only the log can tell them apart.
OUTDIR=$(ls -d "$WS/reviews/PR-$PR/${SHA:0:12}" 2>/dev/null || true)
[ -n "$OUTDIR" ] && "$(dirname "${BASH_SOURCE[0]}")/ci-signal.sh" record "$OUTDIR" "$PR" "$SHA" || true

cd "$REPO"
git worktree remove --force "$WS/worktrees/pr-$PR" 2>/dev/null || true
git update-ref -d "refs/watchdog/pr-$PR" 2>/dev/null || true
echo "recorded PR $PR @ ${SHA:0:12}"
