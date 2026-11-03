#!/usr/bin/env bash
# Prompt evals: static checks always; --agent also runs evals/tasks through $EVAL_AGENT.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# 1. Skill frontmatter and size
for f in "$root"/skills/*/SKILL.md; do
  head -1 "$f" | grep -qx -- '---' || bad "$f: no frontmatter"
  grep -q '^name: ' "$f" || bad "$f: no name"
  grep -q '^description: ' "$f" || bad "$f: no description"
  [[ $(wc -l < "$f") -le 150 ]] || bad "$f: over 150 lines"
done
[[ $(wc -l < "$root/sdlc/templates/design.md") -le 150 ]] || bad 'design template over 150 lines'

# 2. Relative Markdown links resolve
while IFS= read -r f; do
  dir="$(dirname "$f")"
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -z "$target" || "$target" == http* || "$target" == mailto:* ]] && continue
    [[ -e "$dir/$target" ]] || bad "$f: broken link $target"
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
done < <(find "$root/skills" "$root/sdlc" "$root/evals" "$root/README.md" "$root/AGENTS.md" -name '*.md' -not -path '*/out/*')

# 3. agents.yml: no self-review
phase() { sed -nE "s/^  $1: *([a-z]+).*/\1/p" "$root/sdlc/agents.yml"; }
d=$(phase design); g=$(phase goldfish); i=$(phase implement); r=$(phase review); t=$(phase tiebreak)
for a in "$d" "$g" "$i" "$r" "$t"; do
  [[ " claude codex grok gemini " == *" $a "* ]] || bad "agents.yml: unknown agent '$a'"
done
[[ "$g" != "$d" ]] || bad 'agents.yml: goldfish equals design'
[[ "$r" != "$i" ]] || bad 'agents.yml: review equals implement'
[[ "$t" != "$i" && "$t" != "$r" ]] || bad 'agents.yml: tiebreak equals implement or review'
# The resolver accepts the table when every agent with a command is installed.
tmp="$(mktemp -d)"; : > "$tmp/conf"
for a in claude codex grok gemini; do printf '#!/bin/sh\n' > "$tmp/$a"; chmod +x "$tmp/$a"; printf '%s_bin=%s\n' "$a" "$tmp/$a" >> "$tmp/conf"; done
bash "$root/scripts/resolve-agents.sh" "$root/sdlc/agents.yml" "$tmp/conf" > /dev/null || bad 'agents.yml: rejected by scripts/resolve-agents.sh'
rm -rf "$tmp"
for l in $(sed -nE '/^goldfish_lenses:/,/^[a-z]/ s/^  (bug|feature): *//p' "$root/sdlc/agents.yml"); do
  [[ " comprehension adversarial security testability simplicity " == *" $l "* ]] || bad "agents.yml: unknown goldfish lens '$l'"
done

# 4. Agent evals
if [[ "${1:-}" == '--agent' ]]; then
  [[ -n "${EVAL_AGENT:-}" ]] || { echo 'set EVAL_AGENT, e.g. EVAL_AGENT="claude -p"'; exit 2; }
  mkdir -p "$root/evals/out"
  for task in "$root"/evals/tasks/*.md; do
    name="$(basename "$task" .md)"; out="$root/evals/out/$name.md"
    prompt="$(sed -n 's/^Prompt: //p' "$task") (Library: $root)"
    # shellcheck disable=SC2086
    printf '%s\n' "$prompt" | $EVAL_AGENT > "$out" 2>/dev/null || bad "$name: agent failed"
    icase=''; grep -q 'case-insensitive' "$task" && icase='-i'
    while IFS= read -r want; do
      grep -qF $icase -- "$want" "$out" || bad "$name: missing '$want'"
    done < <(sed -nE 's/^- `(.*)`$/\1/p' "$task")
    nope="$(sed -nE 's/^Fail if \(grep\): `(.*)`$/\1/p' "$task")"
    [[ -z "$nope" ]] || ! grep -qiF -- "$nope" "$out" || bad "$name: contains '$nope'"
    max="$(sed -nE 's/^Max lines: ([0-9]+)$/\1/p' "$task")"
    [[ -z "$max" || $(wc -l < "$out") -le $max ]] || bad "$name: over $max lines"
    echo "ran $name"
  done
fi

[[ $fails -eq 0 ]] && echo 'evals: all checks passed' || { echo "evals: $fails failure(s)"; exit 1; }
