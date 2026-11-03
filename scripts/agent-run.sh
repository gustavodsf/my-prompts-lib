#!/usr/bin/env bash
# Run one SDLC phase with the agent resolved from agents.yml, under lane guardrails.
# Usage: agent-run.sh <phase> <prompt-file> <cwd> [metrics.md]
#        agent-run.sh goldfish-panel <prompt-file> <cwd> [metrics.md] [bug|feature]
# The panel runs one context-free reviewer per lens in parallel, alternating goldfish_agents,
# prints each lens report and a final `PANEL: PASS|PARTIAL|FAIL` line, and keeps no files.
#        agent-run.sh diff-lines <cwd> <since-ref>   -> "<added+removed> <checkpoint threshold>"
#        agent-run.sh pseudo-check <cwd>             -> lists leftover SDLC-PSEUDO markers, exit 1 if any
# Lives in the lane runner directory beside project.conf and lanes/agents.yml.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  diff-lines)
    cwd="${2:?cwd}"; since="${3:?since-ref}"
    limit="$(sed -nE 's/^checkpoint_lines=([0-9]+)$/\1/p' "$here/project.conf" 2>/dev/null | head -1)"
    [[ -n "$limit" ]] || limit="$(sed -nE 's/^checkpoint_lines: *([0-9]+).*/\1/p' "$here/lanes/agents.yml" | head -1)"
    # Committed since the ref plus uncommitted work, Markdown excluded (never committed).
    n="$(git -C "$cwd" diff --numstat "$since" -- . ':(exclude)*.md' | awk '$1 != "-" {s += $1 + $2} END {print s + 0}')"
    printf '%s %s\n' "$n" "${limit:-250}"; exit 0 ;;
  pseudo-check)
    cwd="${2:?cwd}"
    if git -C "$cwd" grep -n -I --untracked 'SDLC-PSEUDO' -- . ':(exclude)*.md'; then
      echo 'pseudocode markers remain: implement or remove them before the PR' >&2; exit 1
    fi
    exit 0 ;;
esac
phase="${1:?phase}"; prompt_file="${2:?prompt file}"; cwd="${3:?cwd}"; metrics="${4:-}"
conf="$here/project.conf"; table="$here/lanes/agents.yml"
[[ -f "$prompt_file" && -d "$cwd" ]] || { echo "agent-run: prompt file or cwd missing" >&2; exit 2; }
case "$phase" in design|goldfish|goldfish-panel|implement|review|tiebreak) ;; *) echo "agent-run: unknown phase $phase" >&2; exit 2 ;; esac

resolved="$("$here/resolve-agents.sh" "$table" "$conf" ${APOLO_SDLC_IMPLEMENTER:+--implementer "$APOLO_SDLC_IMPLEMENTER"})"

# Guardrails: only the lane's own claude session pushes. Every agent run here gets no GitHub
# token, no credential prompts, and a push URL that cannot work.
export APOLO_SDLC_LANE="${APOLO_SDLC_LANE:-issue}"
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0=no-push://agent-run.disabled \
  GIT_CONFIG_KEY_1=remote.pushDefault GIT_CONFIG_VALUE_1=no-push-disabled

q() { printf '%q' "$1"; }
metric() { # phase agent status seconds
  [[ -n "$metrics" ]] || return 0
  [[ -f "$metrics" ]] || printf '| Phase | Agent | Tokens (if known) | Attempt | Result |\n| --- | --- | --- | --- | --- |\n' > "$metrics"
  local attempt=$(( $(grep -c "^| $1 | " "$metrics" || true) + 1 ))
  printf '| %s | %s | — | %s | %s, %ss |\n' "$1" "$2" "$attempt" "$3" "$4" >> "$metrics"
}
run_agent() { # agent phase prompt-file
  local agent="$1" ph="$2" prompt="$3" bin template cmd sandbox=read-only
  bin="$(sed -nE "s/^${agent}_bin=(.*)$/\1/p" "$conf" | head -1)"
  template="$(sed -nE "/^commands:/,/^[a-z]/ s/^  $agent: *'(.*)'.*$/\1/p" "$table" | head -1)"
  [[ "$ph" == implement || "$ph" == design ]] && sandbox=workspace-write
  cmd="${template//\{bin\}/$(q "$bin")}"
  cmd="${cmd//\{prompt_file\}/$(q "$prompt")}"
  cmd="${cmd//\{cwd\}/$(q "$cwd")}"
  cmd="${cmd//\{sandbox\}/$sandbox}"
  cmd="${cmd//\{deny_file\}/$(q "$here/lanes/deny.json")}"
  (cd "$cwd" && APOLO_SDLC_PHASE="$ph" APOLO_SDLC_AGENT="$agent" bash -c "$cmd")
}

if [[ "$phase" != goldfish-panel ]]; then
  agent="$(sed -nE "s/^$phase=//p" <<< "$resolved")"
  if [[ "$agent" == blocked || "$agent" == human ]]; then
    echo "agent-run: no independent agent for $phase ($agent)"; exit 3
  fi
  start=$(date +%s); status=0
  run_agent "$agent" "$phase" "$prompt_file" || status=$?
  metric "$phase" "$agent" "exit $status" "$(( $(date +%s) - start ))"
  exit "$status"
fi

# Goldfish panel.
type="${5:-feature}"; [[ "$type" == bug ]] || type=feature
lenses="$(sed -nE "/^goldfish_lenses:/,/^[a-z]/ s/^  $type: *//p" "$table")"
IFS=, read -r -a pool <<< "$(sed -nE 's/^goldfish_pool=//p' <<< "$resolved")"
[[ -n "$lenses" && ${#pool[@]} -gt 0 ]] || { echo "agent-run: no goldfish lenses or agents" >&2; exit 2; }
declare -A focus=(
  [comprehension]='Explain the plan back in at most 10 lines; list every path#symbol not in codemap.md and not marked (new).'
  [adversarial]='Find edge cases, races, bad inputs and failure modes the design misses; say how it could break.'
  [security]='Check secrets, permissions, AWS use (read-only at most), personal data and privacy.'
  [testability]='Check every AC names a concrete, automatable test and every task has a file and a failing test first.'
  [simplicity]='Find over-scope and a simpler option that meets the same ACs.'
)
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
i=0; pids=()
for lens in $lenses; do
  [[ -n "${focus[$lens]:-}" ]] || { echo "agent-run: unknown goldfish lens $lens" >&2; exit 2; }
  agent="${pool[$(( i % ${#pool[@]} ))]}"
  { cat "$prompt_file"; printf '\n\nLens: %s. %s\nReply with a first line `Verdict: Pass|Partial|Fail`, then at most 5 bullets. Do not write files.\n' "$lens" "${focus[$lens]}"; } > "$work/$lens.prompt"
  ( start=$(date +%s); status=0
    run_agent "$agent" goldfish "$work/$lens.prompt" > "$work/$lens.out" 2>&1 || status=$?
    printf '%s %s %s\n' "$agent" "$status" "$(( $(date +%s) - start ))" > "$work/$lens.meta" ) &
  pids+=($!); i=$((i + 1))
done
for pid in "${pids[@]}"; do wait "$pid" || true; done

panel=PASS
for lens in $lenses; do
  read -r agent status secs < "$work/$lens.meta"
  verdict="$(grep -m1 -oiE 'Verdict:[[:space:]]*\**(Pass|Partial|Fail)' "$work/$lens.out" | grep -oiE 'Pass|Partial|Fail' | tail -1 || true)"
  verdict="${verdict,,}"; [[ "$status" == 0 && -n "$verdict" ]] || verdict=fail # no readable verdict blocks
  [[ "$verdict" == fail ]] && panel=FAIL
  [[ "$verdict" == partial && "$panel" == PASS ]] && panel=PARTIAL
  printf '### %s (%s): %s\n' "$lens" "$agent" "${verdict^}"
  head -n 12 "$work/$lens.out"; printf '\n'
  metric "goldfish:$lens" "$agent" "${verdict^}" "$secs"
done
printf 'PANEL: %s\n' "$panel"
[[ "$panel" != FAIL ]]
