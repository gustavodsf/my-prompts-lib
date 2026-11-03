#!/usr/bin/env bash
# Run one SDLC phase with the agent resolved from agents.yml, under lane guardrails.
# Usage: agent-run.sh <phase> <prompt-file> <cwd> [metrics.md]
# Lives in the lane runner directory beside project.conf and lanes/agents.yml.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
phase="${1:?phase}"; prompt_file="${2:?prompt file}"; cwd="${3:?cwd}"; metrics="${4:-}"
conf="$here/project.conf"; table="$here/lanes/agents.yml"
[[ -f "$prompt_file" && -d "$cwd" ]] || { echo "agent-run: prompt file or cwd missing" >&2; exit 2; }
case "$phase" in design|goldfish|implement|review|tiebreak) ;; *) echo "agent-run: unknown phase $phase" >&2; exit 2 ;; esac

resolved="$("$here/resolve-agents.sh" "$table" "$conf" ${APOLO_SDLC_IMPLEMENTER:+--implementer "$APOLO_SDLC_IMPLEMENTER"})"
agent="$(sed -nE "s/^$phase=//p" <<< "$resolved")"
if [[ "$agent" == blocked || "$agent" == human ]]; then
  echo "agent-run: no independent agent for $phase ($agent)"; exit 3
fi
bin="$(sed -nE "s/^${agent}_bin=(.*)$/\1/p" "$conf" | head -1)"
template="$(sed -nE "/^commands:/,/^[a-z]/ s/^  $agent: *'(.*)'.*$/\1/p" "$table" | head -1)"
sandbox=read-only; [[ "$phase" == implement || "$phase" == design ]] && sandbox=workspace-write

q() { printf '%q' "$1"; }
cmd="${template//\{bin\}/$(q "$bin")}"
cmd="${cmd//\{prompt_file\}/$(q "$prompt_file")}"
cmd="${cmd//\{cwd\}/$(q "$cwd")}"
cmd="${cmd//\{sandbox\}/$sandbox}"
cmd="${cmd//\{deny_file\}/$(q "$here/lanes/deny.json")}"

# Guardrails: only the lane's own claude session pushes. Every agent run here gets no GitHub
# token, no credential prompts, and a push URL that cannot work.
export APOLO_SDLC_LANE="${APOLO_SDLC_LANE:-issue}" APOLO_SDLC_PHASE="$phase" APOLO_SDLC_AGENT="$agent"
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0=no-push://agent-run.disabled \
  GIT_CONFIG_KEY_1=remote.pushDefault GIT_CONFIG_VALUE_1=no-push-disabled

start=$(date +%s); status=0
(cd "$cwd" && bash -c "$cmd") || status=$?
if [[ -n "$metrics" ]]; then
  [[ -f "$metrics" ]] || printf '| Phase | Agent | Tokens (if known) | Attempt | Result |\n| --- | --- | --- | --- | --- |\n' > "$metrics"
  attempt=$(( $(grep -c "^| $phase | " "$metrics" || true) + 1 ))
  printf '| %s | %s | — | %s | exit %s, %ss |\n' "$phase" "$agent" "$attempt" "$status" "$(( $(date +%s) - start ))" >> "$metrics"
fi
exit "$status"
