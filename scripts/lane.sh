#!/usr/bin/env bash

set -euo pipefail

runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$runner_dir/project.conf"
claude_bin="${CLAUDE_BIN:-claude}"
gh_bin="${GH_BIN:-gh}"
git_bin="${GIT_BIN:-git}"
codex_bin="${CODEX_BIN:-codex}"
required_keys=(repo owner checkout worktrees docs state evidence_branch)
seen_keys=" "

usage() {
  cat <<'EOF'
Usage: lane.sh issue|ci

Runs one scheduled autonomous lane using project.conf beside this runner.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 1 ]] || { usage >&2; exit 1; }
lane="$1"
[[ "$lane" == 'issue' || "$lane" == 'ci' ]] || fail "unknown lane: $lane"

read_config() {
  local line key value

  [[ -f "$config_file" && ! -L "$config_file" ]] || fail "missing or unsafe project.conf: $config_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || fail "malformed project.conf line: $line"
    key="${line%%=*}"
    value="${line#*=}"
    case " ${required_keys[*]} " in
      *" $key "*) ;;
      *) fail "unsupported project.conf key: $key" ;;
    esac
    [[ "$seen_keys" != *" $key "* ]] || fail "duplicate project.conf key: $key"
    # Values reach cron lines and the prompt, so reject anything cron or a terminal could reinterpret.
    [[ -n "$value" && "$value" != *%* && ! "$value" =~ [^[:print:]] ]] || fail "unsafe project.conf value for $key"
    seen_keys+="$key "
    printf -v "conf_$key" '%s' "$value"
  done < "$config_file"

  for key in "${required_keys[@]}"; do
    [[ "$seen_keys" == *" $key "* ]] || fail "project.conf is missing $key"
  done
}

require_tool() {
  command -v "$2" >/dev/null 2>&1 || fail "$1 is required but was not found: $2"
}

read_config
require_tool claude "$claude_bin"
require_tool gh "$gh_bin"
require_tool git "$git_bin"
[[ "$lane" != 'issue' ]] || require_tool codex "$codex_bin"
