#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
monitor="$repo_root/scripts/monitor.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$monitor" ]] || fail "expected executable monitor: $monitor"

fake_bin="$test_root/bin"
state_file="$test_root/authorized-issue"
log_file="$test_root/calls.log"
mkdir -p "$fake_bin" "$test_root/repository/.git"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "gh %s\\n" "$*" >> "$MONITOR_LOG"' \
  'case "$1 $2" in' \
  '  "issue list") printf "[{\\\"number\\\":7},{\\\"number\\\":42}]\\n" ;;' \
  '  "pr list") printf "[{\\\"number\\\":9}]\\n" ;;' \
  'esac' > "$fake_bin/gh"
chmod +x "$fake_bin/gh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "claude %s\\n" "$*" >> "$MONITOR_LOG"' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$test_root/repository" --state-file "$state_file" --dry-run > "$test_root/dry-run.out"

grep -q '^gh issue list' "$log_file" || fail 'monitor did not list issues'
grep -q '^gh pr list' "$log_file" || fail 'monitor did not list pull requests'
if grep -q '^claude ' "$log_file"; then
  fail 'dry run invoked Claude'
fi

linked_state="$test_root/linked-state"
printf '42\n' > "$test_root/external-state"
ln -s "$test_root/external-state" "$linked_state"
if PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --authorize 42 --state-file "$linked_state"; then
  fail 'monitor accepted a symbolic-link state file'
fi

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --authorize 42 --state-file "$state_file"
[[ "$(<"$state_file")" == '42' ]] || fail 'monitor did not persist the authorized issue'

: > "$log_file"
mkdir "${state_file}.lock"
PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$test_root/repository" --state-file "$state_file"
if grep -q '^claude ' "$log_file"; then
  fail 'monitor invoked Claude while the authorized issue was locked'
fi
rmdir "${state_file}.lock"

: > "$log_file"
PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$test_root/repository" --state-file "$state_file"

grep -q '^gh issue list' "$log_file" || fail 'authorized monitor did not list issues'
grep -q '^gh pr list' "$log_file" || fail 'authorized monitor did not list pull requests'
grep -q '^claude ' "$log_file" || fail 'authorized monitor did not invoke Claude'
grep -q '#42' "$log_file" || fail 'monitor did not pass the authorized issue to Claude'
if grep -q '#7' "$log_file" || grep -Eqi '^gh (aws |issue comment|pr create)' "$log_file"; then
  fail 'monitor invoked an unauthorized or direct-write operation'
fi

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --clear-authorization --state-file "$state_file"
[[ ! -e "$state_file" ]] || fail 'monitor did not clear the authorization state'

printf 'PASS: monitor behavior\n'
