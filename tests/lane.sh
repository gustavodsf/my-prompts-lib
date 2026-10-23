#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lane_source="$repo_root/scripts/lane.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$lane_source" ]] || fail "expected executable lane runner: $lane_source"

fake_bin="$test_root/bin"
call_log="$test_root/calls.log"
mkdir -p "$fake_bin"
for tool in claude gh git codex; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '$tool %s\\n' \"\$*\" >> \"\$LANE_TEST_LOG\"" > "$fake_bin/$tool"
  chmod +x "$fake_bin/$tool"
done

checkout="$test_root/checkout"
mkdir -p "$checkout"

new_runner() {
  local runner="$test_root/runners/$1"
  mkdir -p "$runner"
  cp "$lane_source" "$runner/lane.sh"
  chmod 700 "$runner/lane.sh"
  printf '%s\n' "$runner"
}

write_valid_conf() {
  printf '%s\n' \
    'repo=acme/demo' \
    'owner=acme-owner' \
    "checkout=$checkout" \
    "worktrees=$test_root/worktrees" \
    "docs=$test_root/docs" \
    "state=$1/state" \
    'evidence_branch=qa-evidence' > "$1/project.conf"
}

run_lane() {
  local runner="$1"
  shift
  LANE_TEST_LOG="$call_log" \
    CLAUDE_BIN="${CLAUDE_BIN:-$fake_bin/claude}" GH_BIN="${GH_BIN:-$fake_bin/gh}" \
    GIT_BIN="${GIT_BIN:-$fake_bin/git}" CODEX_BIN="${CODEX_BIN:-$fake_bin/codex}" \
    "$runner/lane.sh" "$@"
}

expect_rejection() {
  local description="$1" expected_message="$2" runner="$3"
  shift 3
  : > "$call_log"
  if run_lane "$runner" "$@" > "$test_root/out" 2> "$test_root/err"; then
    fail "lane accepted $description"
  fi
  grep -qi -- "$expected_message" "$test_root/err" || fail "lane did not explain $description: $(cat "$test_root/err")"
  if grep -q '^claude ' "$call_log"; then
    fail "lane invoked Claude despite $description"
  fi
}

runner="$(new_runner valid)"
write_valid_conf "$runner"
run_lane "$runner" issue || fail 'lane rejected a valid issue configuration'
run_lane "$runner" ci || fail 'lane rejected a valid ci configuration'

expect_rejection 'a missing lane name' 'usage' "$runner"
expect_rejection 'an unknown lane' 'unknown lane' "$runner" deploy
expect_rejection 'extra arguments' 'usage' "$runner" issue extra

missing="$(new_runner missing)"
expect_rejection 'a missing project.conf' 'project.conf' "$missing" issue

unknown="$(new_runner unknown)"
write_valid_conf "$unknown"
printf 'token=secret\n' >> "$unknown/project.conf"
expect_rejection 'an unknown configuration key' 'unsupported' "$unknown" issue

duplicate="$(new_runner duplicate)"
write_valid_conf "$duplicate"
printf 'owner=someone-else\n' >> "$duplicate/project.conf"
expect_rejection 'a duplicate configuration key' 'duplicate' "$duplicate" issue

malformed="$(new_runner malformed)"
write_valid_conf "$malformed"
printf 'continued value without a key\n' >> "$malformed/project.conf"
expect_rejection 'a line without a key' 'malformed' "$malformed" issue

percent="$(new_runner percent)"
write_valid_conf "$percent"
sed -i 's|^docs=.*|docs=/tmp/100%docs|' "$percent/project.conf"
expect_rejection 'a value containing a percent sign' 'unsafe' "$percent" issue

carriage="$(new_runner carriage)"
write_valid_conf "$carriage"
sed -i 's|^owner=.*|owner=acme\r|' "$carriage/project.conf"
expect_rejection 'a value containing a control character' 'unsafe' "$carriage" issue

incomplete="$(new_runner incomplete)"
write_valid_conf "$incomplete"
sed -i '/^checkout=/d' "$incomplete/project.conf"
expect_rejection 'a missing required key' 'checkout' "$incomplete" issue

linked="$(new_runner linked)"
mkdir -p "$test_root/linked-target"
write_valid_conf "$test_root/linked-target"
ln -s "$test_root/linked-target/project.conf" "$linked/project.conf"
expect_rejection 'a symbolic-link project.conf' 'project.conf' "$linked" issue

absent="$test_root/absent"
CLAUDE_BIN="$absent/claude" expect_rejection 'a missing claude executable' 'claude' "$runner" issue
GH_BIN="$absent/gh" expect_rejection 'a missing gh executable' 'gh' "$runner" ci
GIT_BIN="$absent/git" expect_rejection 'a missing git executable' 'git' "$runner" ci
CODEX_BIN="$absent/codex" expect_rejection 'a missing codex executable for the issue lane' 'codex' "$runner" issue
CODEX_BIN="$absent/codex" run_lane "$runner" ci || fail 'ci lane required codex'

printf 'PASS: lane behavior\n'
