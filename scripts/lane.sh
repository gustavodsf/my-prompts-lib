#!/usr/bin/env bash

set -euo pipefail

runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$runner_dir/project.conf"
prompt_keys=(repo owner checkout worktrees docs state evidence_branch)
required_keys=("${prompt_keys[@]}" claude_bin gh_bin git_bin)
optional_keys=(codex_bin)
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
  # The installer validates in the same locale, so a value it accepts is never rejected under cron.
  local LC_ALL=C

  [[ -f "$config_file" && ! -L "$config_file" ]] || fail "missing or unsafe project.conf: $config_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || fail "malformed project.conf line: $line"
    key="${line%%=*}"
    value="${line#*=}"
    case " ${required_keys[*]} ${optional_keys[*]} " in
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
  local value="conf_$1_bin"

  [[ -n "${!value:-}" ]] || fail "$1 is required but project.conf has no $1_bin"
  [[ "${!value}" == /* ]] || fail "$1_bin must be an absolute path: ${!value}"
  [[ -f "${!value}" && -x "${!value}" ]] || fail "$1 is required but was not found: ${!value}"
}

lock_dir="$runner_dir/lanes.lock"

# mkdir is atomic and portable; flock is unavailable on macOS.
acquire_lock() {
  local holder

  if ! mkdir "$lock_dir" 2>/dev/null; then
    holder="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [[ "$holder" =~ ^[0-9]+$ ]] && kill -0 "$holder" 2>/dev/null; then
      return 1
    fi
    rm -rf -- "$lock_dir"
    mkdir "$lock_dir" 2>/dev/null || return 1
  fi
  trap 'rm -rf -- "$lock_dir"' EXIT
  printf '%s\n' "$$" > "$lock_dir/pid"
  chmod 700 "$lock_dir"
}

build_prompt() {
  local key value

  printf 'Lane mode: active\n'
  printf 'lane: %s\n' "$lane"
  for key in "${prompt_keys[@]}"; do
    value="conf_$key"
    printf '%s: %s\n' "$key" "${!value}"
  done
  printf '\n'
  cat "$prompt_file"
}

read_config
require_tool claude
require_tool gh
require_tool git
[[ "$lane" != 'issue' ]] || require_tool codex

prompt_file="$runner_dir/lanes/$lane.md"
deny_file="$runner_dir/lanes/deny.json"
log_dir="$runner_dir/logs"
[[ -f "$prompt_file" ]] || fail "lane prompt is missing: $prompt_file"
[[ -f "$deny_file" ]] || fail "deny rules are missing: $deny_file"
[[ -d "$conf_checkout" ]] || fail "checkout is not a directory: $conf_checkout"

acquire_lock || exit 0

mkdir -p "$log_dir"
chmod 700 "$log_dir"
prompt_copy="$lock_dir/prompt"
build_prompt > "$prompt_copy"
status=0
{
  printf '=== %s %s lane start ===\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$lane"
  (cd "$conf_checkout" && APOLO_SDLC_LANE="$lane" "$conf_claude_bin" -p --dangerously-skip-permissions --settings "$deny_file" < "$prompt_copy") || status=$?
  printf '=== %s %s lane exit %s ===\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$lane" "$status"
} >> "$log_dir/$lane.log" 2>&1
exit "$status"
