#!/usr/bin/env bash
# Resolve sdlc/agents.yml into the effective agent per phase, applying the fallback rule.
# Usage: resolve-agents.sh <agents.yml> [project.conf] [--implementer AGENT]
# Prints `phase=agent` lines; exits 1 when the table is invalid or a write phase has no agent.
# An agent is available when its command is non-empty and its binary is known
# (`<agent>_bin` in project.conf when given, otherwise found on PATH).
set -euo pipefail
table="${1:?usage: resolve-agents.sh <agents.yml> [project.conf] [--implementer AGENT]}"; shift
conf=""; implementer=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --implementer) implementer="${2:?}"; shift 2 ;;
    *) conf="$1"; shift ;;
  esac
done
[[ -f "$table" ]] || { echo "agents table not found: $table" >&2; exit 1; }
known=(claude codex grok gemini)

phase_of() { sed -nE "/^phases:/,/^[a-z]/ s/^  $1: *([a-z]+).*/\1/p" "$table" | head -1; }
command_of() { sed -nE "/^commands:/,/^[a-z]/ s/^  $1: *'(.*)'.*$/\1/p" "$table" | head -1; }
writers=" $(sed -nE 's/^write_capable: *//p' "$table") "

available() {
  local agent="$1" bin=""
  [[ -n "$(command_of "$agent")" ]] || return 1
  if [[ -n "$conf" ]]; then
    bin="$(sed -nE "s/^${agent}_bin=(.*)$/\1/p" "$conf" | head -1)"
    [[ -n "$bin" && -x "$bin" ]]
  else
    command -v "$agent" >/dev/null 2>&1
  fi
}
die() { echo "agents.yml: $1" >&2; exit 1; }

for p in design goldfish implement review tiebreak; do
  a="$(phase_of "$p")"
  [[ -n "$a" ]] || die "phase $p is missing"
  [[ " ${known[*]} " == *" $a "* ]] || die "phase $p uses unknown agent '$a'"
done

# Write phases: the configured agent or nothing.
design="$(phase_of design)"
[[ "$writers" == *" $design "* ]] || die "design agent $design is not write-capable"
available "$design" || die "design agent $design is not available (set ${design}_bin or its command)"
impl="${implementer:-$(phase_of implement)}"
[[ "$writers" == *" $impl "* ]] || die "implement agent $impl is not write-capable"
available "$impl" || die "implement agent $impl is not available (set ${impl}_bin or its command)"

# Read phases: configured agent if available and independent, else the first available
# agent in the fixed order that keeps independence, else the phase's last resort.
pick() {
  local want="$1" last="$2"; shift 2
  local candidate
  for candidate in "$want" "${known[@]}"; do
    [[ " $* " == *" $candidate "* ]] && continue
    available "$candidate" && { echo "$candidate"; return; }
  done
  echo "$last"
}
# Goldfish independence comes from a fresh process with no history, so the design agent may
# serve as fallback (a new claude process is still a clean context).
goldfish="$(phase_of goldfish)"; available "$goldfish" || goldfish="$design"
review="$(pick "$(phase_of review)" blocked "$impl")"
tiebreak="$(pick "$(phase_of tiebreak)" human "$impl" "$review")"

pool=""
for a in $(sed -nE 's/^goldfish_agents: *//p' "$table"); do
  [[ " ${known[*]} " == *" $a "* ]] || die "goldfish_agents uses unknown agent '$a'"
  available "$a" && pool="${pool:+$pool,}$a"
done
[[ -n "$pool" ]] || pool="$design"
printf 'design=%s\ngoldfish=%s\nimplement=%s\nreview=%s\ntiebreak=%s\ngoldfish_pool=%s\n' "$design" "$goldfish" "$impl" "$review" "$tiebreak" "$pool"
