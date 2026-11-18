#!/usr/bin/env bash
# check-panel.sh <outDir>
# Refuses a run whose panel is not 1–2 Codex/Grok lanes with the orchestrator as reconciler.
#
# Exit 0 => the panel is valid. Exit 1 => it is not, and nothing downstream should treat
# its agreement counts as confidence.
set -euo pipefail

OUT="${1:?usage: check-panel.sh <outDir>}"
FAIL=0
say() { printf '%s\n' "$1" >&2; FAIL=1; }

# 1. lane files must be lane-codex.md and/or lane-grok.md, at least one, at most two
mapfile -t FILES < <(find "$OUT" -maxdepth 1 -name 'lane-*.md' | sort)
COUNT=${#FILES[@]}
[ "$COUNT" -ge 1 ] && [ "$COUNT" -le 2 ] || say "Panel must have 1 or 2 lane files, found $COUNT."
ALLOWED=' lane-codex.md lane-grok.md '
for f in "${FILES[@]}"; do
  base="$(basename "$f")"
  [[ "$ALLOWED" == *" $base "* ]] || say "Unexpected lane file: $base (only lane-codex.md and lane-grok.md are allowed)."
  [ -s "$f" ] || say "Lane file is empty: $base"
done

# 2. models.json records the CLIs that ran and that the orchestrator reconciled
if [ ! -s "$OUT/models.json" ]; then
  say "models.json missing — cannot tell which CLIs the panel ran on."
else
  LANES=$(jq -r 'if (.lanes | type) == "array" then .lanes | join(",") else .lanes // "unset" end' "$OUT/models.json")
  RECON=$(jq -r '.reconciler // "unset"' "$OUT/models.json")
  [ "$RECON" = "orchestrator" ] || say "Reconciler recorded as '$RECON', must be orchestrator."
  IFS=',' read -r -a listed <<< "$LANES"
  [ "${#listed[@]}" -ge 1 ] && [ "${#listed[@]}" -le 2 ] || say "Lanes recorded as '$LANES', must be one or both of codex, grok."
  for a in "${listed[@]}"; do
    a="${a// /}"
    [ "$a" = "codex" ] || [ "$a" = "grok" ] || say "Lane '$a' is not allowed (only codex and grok)."
    [ -s "$OUT/lane-$a.md" ] || say "models.json lists $a but lane-$a.md is missing."
  done
  for f in "${FILES[@]}"; do
    base="$(basename "$f" .md)"
    agent="${base#lane-}"
    [[ ",$LANES," == *",$agent,"* || "$LANES" == *"$agent"* ]] || say "$base exists but is not listed in models.json lanes ($LANES)."
  done
fi

if [ "$FAIL" -ne 0 ]; then
  cat >&2 <<'MSG'

This run is not a valid 1–2-lane Codex/Grok review. Do not present its agreement
counts as confidence. Say so at the top of the report, and re-run with lane-codex.md
and/or lane-grok.md, models.json lanes of "codex" and/or "grok", and reconciler
"orchestrator".
MSG
  exit 1
fi

echo "panel ok: ${COUNT} lane(s) ($LANES); reconciler orchestrator"
