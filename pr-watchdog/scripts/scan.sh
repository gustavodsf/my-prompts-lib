#!/usr/bin/env bash
# Emits JSON array of PRs whose head SHA differs from the last reviewed SHA, with a
# `deferred` flag on any whose head commit is younger than the debounce window.
# State lives outside the repo so the watchdog never dirties git status.
set -euo pipefail

REPO="${WATCHDOG_REPO:-$HOME/dev/Delivery-API}"
WS="${WATCHDOG_WS:-$HOME/dev/.pr-watchdog}"
STATE="$WS/state.json"
LIMIT="${WATCHDOG_LIMIT:-30}"

# Skip PRs still being actively written. Measured 2026-08-26: PRs mid-development push about
# hourly (3015, 3020), so every intermediate state drew a full five-lane review and none of
# those states merged. PRs responding to review feedback push days apart (2995) and this
# window never touches them -- commit cadence separates the two cases by itself.
DEBOUNCE_HOURS="${WATCHDOG_DEBOUNCE_HOURS:-2}"

# Ceiling at the other end. Six of the twelve pending PRs had not been touched in 57-153
# days; reviewing them at ~163k output tokens each is ~978k spent on work nobody is doing.
# Stale PRs are still listed, flagged, and reviewable on request -- just not swept
# automatically. 0 disables the ceiling.
STALE_DAYS="${WATCHDOG_STALE_DAYS:-30}"

# Hard cap on how much of a 5-hour session window the watchdog may take. The session cap --
# not the weekly -- is the binding constraint, and it is the same window the human needs for
# their own work. Measured 2026-08-26: weekly sat at 8% while one session hit 61% on
# watchdog runs alone. At ~163k output tokens per review, two reviews is roughly a third of a
# window; five would take most of it.
MAX_PER_WINDOW="${WATCHDOG_MAX_PER_WINDOW:-2}"
WINDOW_HOURS="${WATCHDOG_WINDOW_HOURS:-5}"

# Pin gh to one account, immune to a concurrent `gh auth switch` in another shell.
. "$(dirname "${BASH_SOURCE[0]}")/_gh-account.sh"

mkdir -p "$WS"
[ -f "$STATE" ] || echo '{}' > "$STATE"

# Forward-only watermark. The routine reviews PRs that arrive from now on; it does not sweep
# whatever was already open when it started. Without this, the first run queued all 13 open
# PRs -- six of them untouched for 57-153 days -- which is a backlog audit, not a watch.
#
# It is a FLOOR, not a moving cursor: it only excludes PRs whose head commit predates the
# watchdog. Per-PR SHA state handles everything after it, so a PR deferred by the debounce
# stays a candidate on the next scan instead of being skipped past forever.
WATERMARK=$(jq -r '._watermark // ""' "$STATE")
if [ -z "$WATERMARK" ]; then
  WATERMARK=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq --arg w "$WATERMARK" '. + {_watermark: $w}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  echo "watermark initialised at $WATERMARK — PRs older than this are not swept automatically." >&2
  echo "Review one explicitly with: /pr-watchdog <number>" >&2
fi

# Reviews already completed inside the current window, counted from recorded reviewedAt.
WINDOW_START=$(( $(date -u +%s) - WINDOW_HOURS * 3600 ))
USED=$(jq -r '[to_entries[] | select(.key|startswith("_")|not) | .value.reviewedAt // empty]
  | map(sub("\\..*Z$";"Z")) | .[]' "$STATE" 2>/dev/null \
  | while read -r t; do
      e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$t" +%s 2>/dev/null || date -u -d "$t" +%s 2>/dev/null || echo 0)
      if [ "$e" -ge "$WINDOW_START" ]; then echo x; fi
    done | wc -l | tr -d ' ')

if [ "$MAX_PER_WINDOW" -gt 0 ] && [ "${USED:-0}" -ge "$MAX_PER_WINDOW" ]; then
  echo "Window budget spent: ${USED}/${MAX_PER_WINDOW} reviews in the last ${WINDOW_HOURS}h." >&2
  echo "Deferring to leave session headroom. Override with WATCHDOG_MAX_PER_WINDOW=0." >&2
  jq -n --argjson used "${USED:-0}" --argjson max "$MAX_PER_WINDOW" \
    '{budgetSpent:true, reviewsInWindow:$used, maxPerWindow:$max, candidates:[]}'
  exit 0
fi

cd "$REPO"

CANDIDATES=$(gh pr list --limit "$LIMIT" \
    --json number,title,headRefName,headRefOid,isDraft,updatedAt,author,additions,deletions \
  | jq --slurpfile st "$STATE" '
      ($st[0] // {}) as $seen
      | map(select(.isDraft == false))
      | map(. + {seenSha: ($seen[(.number|tostring)].sha // "")})
      | map(select(.headRefOid != .seenSha))
      | sort_by(.updatedAt) | reverse
    ')

epoch_of() {
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null || echo 0
}

NOW=$(date -u +%s)
CUTOFF=$(( NOW - DEBOUNCE_HOURS * 3600 ))
WM_EPOCH=$(epoch_of "$WATERMARK")

# Head-commit age is fetched only for the few PRs that already passed the SHA filter, not
# for all 30 open ones. updatedAt cannot serve here: a comment bumps it, which would defer a
# review for as long as people keep talking on the thread.
echo "$CANDIDATES" | jq -c '.[]' | while read -r pr; do
  n=$(printf '%s' "$pr" | jq -r '.number')
  ts=$(gh pr view "$n" --json commits --jq '[.commits[].committedDate] | max' 2>/dev/null || true)

  if [ -z "${ts:-}" ] || [ "$ts" = "null" ]; then
    printf '%s' "$pr" | jq '. + {headCommittedAt: null, deferred: false,
                                 debounce: "commit time unavailable - reviewing"}'
    continue
  fi

  e=$(epoch_of "$ts")
  age_min=$(( (NOW - e) / 60 ))
  if [ "$e" -lt "$WM_EPOCH" ]; then
    printf '%s' "$pr" | jq --arg ts "$ts" --argjson d "$(( age_min / 1440 ))" \
      '. + {headCommittedAt: $ts, deferred: true, preexisting: true, ageDays: $d,
            debounce: "predates the watchdog (\($d)d) - not swept; review on request"}'
  elif [ "$STALE_DAYS" -gt 0 ] && [ "$age_min" -gt $(( STALE_DAYS * 1440 )) ]; then
    printf '%s' "$pr" | jq --arg ts "$ts" --argjson d "$(( age_min / 1440 ))" \
      '. + {headCommittedAt: $ts, deferred: true, stale: true, ageDays: $d,
            debounce: "stale - no commit in \($d) days; review on request only"}'
  elif [ "$e" -gt "$CUTOFF" ]; then
    printf '%s' "$pr" | jq --arg ts "$ts" --argjson m "$age_min" \
      '. + {headCommittedAt: $ts, deferred: true, ageMinutes: $m,
            debounce: "still being worked - last commit \($m)m ago"}'
  else
    printf '%s' "$pr" | jq --arg ts "$ts" --argjson m "$age_min" \
      '. + {headCommittedAt: $ts, deferred: false, ageMinutes: $m}'
  fi
done | jq -s 'sort_by(.updatedAt) | reverse'
