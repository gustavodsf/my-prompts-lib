#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
monitor="$repo_root/scripts/monitor.sh"
monitor_batch="$repo_root/scripts/monitor.bat"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$monitor" ]] || fail "expected executable monitor: $monitor"
[[ -f "$monitor_batch" ]] || fail "expected Windows monitor: $monitor_batch"

fake_bin="$test_root/bin"
state_file="$test_root/authorized-issue"
log_file="$test_root/calls.log"
repo_a="$test_root/repository-a"
repo_b="$test_root/repository-b"
mkdir -p "$fake_bin" "$repo_a" "$repo_b"
git -C "$repo_a" init -q
git -C "$repo_b" init -q
git -C "$repo_a" remote add origin 'https://github.com/acme/repository-a.git'
git -C "$repo_b" remote add origin 'https://github.com/acme/repository-b.git'

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "gh %s\\n" "$*" >> "$MONITOR_LOG"' \
  'case "$1 $2" in' \
  '  "issue list") printf "[{\\\"number\\\":7},{\\\"number\\\":42}]\\n" ;;' \
  '  "pr list") printf "[{\\\"number\\\":9}]\\n" ;;' \
  '  "issue view")' \
  '    for argument in "$@"; do' \
  '      [[ "$argument" == "--jq" ]] && { printf "OPEN\\n"; break; }' \
  '    done' \
  '    ;;' \
  'esac' > "$fake_bin/gh"
chmod +x "$fake_bin/gh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "claude %s\\n" "$*" >> "$MONITOR_LOG"' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --state-file "$state_file" --dry-run > "$test_root/dry-run.out"

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

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --authorize 42 --state-file "$state_file"
grep -qx 'issue=42' "$state_file" || fail 'monitor did not persist the authorized issue'
grep -qx 'remote=https://github.com/acme/repository-a.git' "$state_file" || fail 'monitor did not bind authorization to the repository remote'

if PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_b" --state-file "$state_file"; then
  fail 'monitor used authorization from a different repository'
fi

if PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --state-file "$state_file" --limit 51; then
  fail 'monitor accepted an unbounded polling limit'
fi

: > "$log_file"
mkdir "${state_file}.lock"
printf '%s %s\n' "$$" "$(date +%s)" > "${state_file}.lock/owner"
PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --state-file "$state_file"
if grep -q '^claude ' "$log_file"; then
  fail 'monitor invoked Claude while the authorized issue was locked'
fi
rm "${state_file}.lock/owner"
rmdir "${state_file}.lock"

: > "$log_file"
mkdir "${state_file}.lock"
printf '%s %s\n' '999999' '1' > "${state_file}.lock/owner"
PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --state-file "$state_file" --lock-ttl 1

grep -q '^claude ' "$log_file" || fail 'authorized monitor did not invoke Claude'
grep -q '#42' "$log_file" || fail 'monitor did not pass the authorized issue to Claude'
grep -F "$repo_root/scripts/github-write.sh" "$log_file" >/dev/null || fail 'monitor did not delegate external writes to the constrained wrapper'
grep -qx 'status=completed' "$state_file" || fail 'monitor did not complete the authorized issue after Claude succeeded'
if grep -Eq '^gh (issue list|pr list)' "$log_file"; then
  fail 'authorized monitor performed unnecessary broad polling'
fi
if grep -q '#7' "$log_file" || grep -Eqi '^gh (aws |issue comment|pr create)' "$log_file"; then
  fail 'monitor invoked an unauthorized or direct-write operation'
fi

: > "$log_file"
PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --state-file "$state_file"
if grep -q '^claude ' "$log_file"; then
  fail 'monitor re-invoked Claude after the issue was completed'
fi
if grep -Eq '^gh (issue list|pr list)' "$log_file"; then
  fail 'completed monitor performed unnecessary broad polling'
fi

PATH="$fake_bin:$PATH" MONITOR_LOG="$log_file" "$monitor" --repo "$repo_a" --clear-authorization --state-file "$state_file"
[[ ! -e "$state_file" ]] || fail 'monitor did not clear the authorization state'

if rg -F 'Bash(curl *)' "$monitor_batch" >/dev/null || rg -F 'Bash(git push *)' "$monitor_batch" >/dev/null || rg -F 'Bash(gh issue comment *)' "$monitor_batch" >/dev/null || rg -F 'Bash(gh pr create *)' "$monitor_batch" >/dev/null; then
  fail 'Windows monitor retained direct external-write or curl permissions'
fi
rg -F 'authorize and clear cannot be used together' "$monitor_batch" >/dev/null || fail 'Windows monitor does not reject incompatible authorization flags'
rg -F 'limit must be an integer from 1 to 50' "$monitor_batch" >/dev/null || fail 'Windows monitor does not cap polling'
rg -F 'call :read_state' "$monitor_batch" >/dev/null || fail 'Windows monitor does not validate structured authorization state'
rg -F ':recover_lock' "$monitor_batch" >/dev/null || fail 'Windows monitor does not recover stale locks'

printf 'PASS: monitor behavior\n'
