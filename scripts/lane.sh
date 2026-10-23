#!/usr/bin/env bash

set -euo pipefail

runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$runner_dir/project.conf"
prompt_keys=(repo owner checkout worktrees docs state evidence_branch)
required_keys=("${prompt_keys[@]}" claude_bin gh_bin git_bin)
optional_keys=(codex_bin timeout_seconds max_turns)
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
  conf_timeout_seconds="${conf_timeout_seconds:-3600}"
  conf_max_turns="${conf_max_turns:-150}"
  [[ "$conf_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || fail "timeout_seconds must be a positive integer: $conf_timeout_seconds"
  [[ "$conf_max_turns" =~ ^[1-9][0-9]*$ ]] || fail "max_turns must be a positive integer: $conf_max_turns"
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

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

# Job control gives Claude its own process group, so a timeout also stops the tools it started.
run_with_limit() {
  local limit="$1"
  local child
  local watchdog
  local status=0
  local expired="$lock_dir/expired"
  shift

  set -m
  "$@" &
  child=$!
  (sleep "$limit"; : > "$expired"; kill -TERM -- "-$child" 2>/dev/null; sleep 10; kill -KILL -- "-$child" 2>/dev/null) &
  watchdog=$!
  set +m
  wait "$child" || status=$?
  kill -TERM -- "-$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [[ -e "$expired" ]]; then
    printf '=== %s %s lane timed out after %ss ===\n' "$(timestamp)" "$lane" "$limit"
    return 124
  fi
  return "$status"
}

# The runner passes the token through the environment so the model never reads or types it.
load_bot_token() {
  local token_file="$conf_state/bot-token"

  bot_token=""
  [[ -e "$token_file" || -L "$token_file" ]] || return 0
  [[ -f "$token_file" && ! -L "$token_file" && -O "$token_file" ]] || fail "bot-token must be a regular file you own: $token_file"
  [[ -z "$(find "$token_file" -prune \( -perm -0040 -o -perm -0020 -o -perm -0010 -o -perm -0004 -o -perm -0002 -o -perm -0001 \) -print)" ]] \
    || fail "bot-token must not be accessible by other users: $token_file"
  IFS= read -r bot_token < "$token_file" || true
  [[ "$bot_token" =~ ^[A-Za-z0-9_]+$ ]] || fail "bot-token is malformed: $token_file"
}

run_claude() {
  [[ -z "$bot_token" ]] || export GH_TOKEN="$bot_token"
  cd "$conf_checkout" && APOLO_SDLC_LANE="$lane" exec "$conf_claude_bin" -p --dangerously-skip-permissions \
    --settings "$deny_file" --max-turns "$conf_max_turns" < "$prompt_copy"
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
load_bot_token

prompt_file="$runner_dir/lanes/$lane.md"
deny_file="$runner_dir/lanes/deny.json"
log_dir="$runner_dir/logs"
[[ -f "$prompt_file" ]] || fail "lane prompt is missing: $prompt_file"
[[ -f "$deny_file" ]] || fail "deny rules are missing: $deny_file"
[[ -d "$conf_checkout" ]] || fail "checkout is not a directory: $conf_checkout"

mkdir -p "$log_dir"
chmod 700 "$log_dir"
if ! acquire_lock; then
  printf '=== %s %s lane skipped: lock held by pid %s ===\n' "$(timestamp)" "$lane" "$(cat "$lock_dir/pid" 2>/dev/null || printf unknown)" >> "$log_dir/$lane.log"
  exit 0
fi

prompt_copy="$lock_dir/prompt"
build_prompt > "$prompt_copy"
status=0
{
  printf '=== %s %s lane start ===\n' "$(timestamp)" "$lane"
  run_with_limit "$conf_timeout_seconds" run_claude || status=$?
  printf '=== %s %s lane exit %s ===\n' "$(timestamp)" "$lane" "$status"
} >> "$log_dir/$lane.log" 2>&1
exit "$status"
