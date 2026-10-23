#!/usr/bin/env bash
# check-panel.sh <outDir>
# Refuses a run whose panel is not five lanes on the right models.
#
# The agreement thresholds are calibrated on five independent Opus lanes. A run with
# four lanes, or lanes on another model, produces percentages that look identical and
# mean something different. Neither is visible in summary.md.
#
# Exit 0 => the panel is valid. Exit 1 => it is not, and nothing downstream should treat
# its percentages as confidence.
set -euo pipefail

OUT="${1:?usage: check-panel.sh <outDir>}"
FAIL=0
say() { printf '%s\n' "$1" >&2; FAIL=1; }

# 1. five lane files, one per letter
MISSING=""
for L in a b c d e; do
  [ -s "$OUT/lane-$L.md" ] || MISSING="$MISSING $L"
done
[ -n "$MISSING" ] && say "Panel incomplete: no report from lane(s)$MISSING."

# 2. no extras — a sixth lane means the panel is not what the thresholds assume
EXTRA=$(find "$OUT" -maxdepth 1 -name 'lane-*.md' 2>/dev/null \
        | grep -vE '/lane-[a-e]\.md$' || true)
[ -n "$EXTRA" ] && say "Unexpected lane file(s): $(echo "$EXTRA" | tr '\n' ' ')"

# 3. the models that ran, as recorded at spawn time
if [ ! -s "$OUT/models.json" ]; then
  say "models.json missing — cannot tell which models the panel ran on."
else
  LANES=$(jq -r '.lanes // "unset"' "$OUT/models.json")
  RECON=$(jq -r '.reconciler // "unset"' "$OUT/models.json")
  [ "$LANES" = "opus" ]  || say "Lanes recorded as '$LANES', must be opus."
  [ "$RECON" = "fable" ] || say "Reconciler recorded as '$RECON', must be fable."
fi

if [ "$FAIL" -ne 0 ]; then
  cat >&2 <<'MSG'

This run is not a valid five-lane review. Do not present its agreement percentages as
confidence — they describe a different panel from the one the thresholds were calibrated
on. Say so at the top of the report, and re-run with all five lanes spawned in a single
message, each with model: "opus".
MSG
  exit 1
fi

echo "panel ok: 5 lanes, opus; reconciler fable"
