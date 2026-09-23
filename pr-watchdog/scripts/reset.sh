#!/usr/bin/env bash
# reset.sh [pr-number]  -- forget one PR, or all of them, so it gets re-reviewed.
set -euo pipefail
REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
STATE="$WS/state.json"

if [ $# -eq 0 ]; then
  # Keep _watermark. Wiping it makes the next scan re-stamp it to now, which marks every open
  # PR as predating the watchdog and defers all of them -- a reset would disable the tool.
  # (Brendan Glancy)
  if jq -e 'has("_watermark")' "$STATE" >/dev/null 2>&1; then
    jq '{_watermark}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  else
    echo '{}' > "$STATE"
  fi
  rm -rf "$WS/reviews"
  cd "$REPO"
  git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "$WS/worktrees" | \
    while read -r w; do git worktree remove --force "$w" || true; done
  git for-each-ref --format='%(refname)' refs/watchdog | while read -r r; do git update-ref -d "$r"; done
  echo "state cleared"
else
  jq --arg pr "$1" 'del(.[$pr])' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  rm -rf "$WS/reviews/PR-$1"
  cd "$REPO"
  git worktree remove --force "$WS/worktrees/pr-$1" 2>/dev/null || true
  git update-ref -d "refs/watchdog/pr-$1" 2>/dev/null || true
  echo "forgot PR $1 and deleted its review output"
fi
