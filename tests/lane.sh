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
  mkdir -p "$runner/lanes"
  cp "$lane_source" "$runner/lane.sh"
  chmod 700 "$runner/lane.sh"
  printf 'ISSUE LANE PROMPT\n' > "$runner/lanes/issue.md"
  printf 'CI LANE PROMPT\n' > "$runner/lanes/ci.md"
  printf '{"permissions":{"deny":[]}}\n' > "$runner/lanes/deny.json"
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

no_prompt="$(new_runner no-prompt)"
write_valid_conf "$no_prompt"
rm "$no_prompt/lanes/ci.md"
expect_rejection 'a missing lane prompt' 'prompt' "$no_prompt" ci

no_deny="$(new_runner no-deny)"
write_valid_conf "$no_deny"
rm "$no_deny/lanes/deny.json"
expect_rejection 'missing deny rules' 'deny' "$no_deny" issue

no_checkout="$(new_runner no-checkout)"
write_valid_conf "$no_checkout"
sed -i "s|^checkout=.*|checkout=$test_root/absent-checkout|" "$no_checkout/project.conf"
expect_rejection 'a missing checkout directory' 'checkout' "$no_checkout" issue

recording_claude="$fake_bin/recording-claude"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$@" > "$CLAUDE_RECORD/args"' \
  'printf "%s\n" "${APOLO_SDLC_LANE:-unset}" > "$CLAUDE_RECORD/lane"' \
  'pwd -P > "$CLAUDE_RECORD/cwd"' \
  'cat > "$CLAUDE_RECORD/stdin"' \
  'printf "claude output %s\n" "$APOLO_SDLC_LANE"' \
  'printf "claude warning\n" >&2' \
  'exit "${FAKE_CLAUDE_RC:-0}"' > "$recording_claude"
chmod +x "$recording_claude"
record="$test_root/record"
mkdir -p "$record"

run_recorded() {
  CLAUDE_BIN="$recording_claude" CLAUDE_RECORD="$record" run_lane "$@"
}

executed="$(new_runner executed)"
write_valid_conf "$executed"
run_recorded "$executed" issue > "$test_root/out" || fail 'lane failed with a valid configuration'

expected_args="$(printf '%s\n' -p --dangerously-skip-permissions --settings "$executed/lanes/deny.json")"
[[ "$(cat "$record/args")" == "$expected_args" ]] || fail "lane passed unexpected Claude arguments: $(cat "$record/args")"
[[ "$(cat "$record/lane")" == 'issue' ]] || fail 'lane did not export APOLO_SDLC_LANE'
[[ "$(cat "$record/cwd")" == "$(cd "$checkout" && pwd -P)" ]] || fail 'lane did not run Claude in the checkout'
for expected in 'repo: acme/demo' 'owner: acme-owner' "checkout: $checkout" "worktrees: $test_root/worktrees" \
  "docs: $test_root/docs" "state: $executed/state" 'evidence_branch: qa-evidence' 'lane: issue'; do
  grep -qxF -- "$expected" "$record/stdin" || fail "lane prompt is missing configuration line: $expected"
done
[[ "$(tail -n 1 "$record/stdin")" == 'ISSUE LANE PROMPT' ]] || fail 'lane prompt did not end with the lane instructions'
grep -q 'CI LANE PROMPT' "$record/stdin" && fail 'issue lane received the ci prompt'
[[ ! -s "$test_root/out" ]] || fail 'lane wrote Claude output to standard output instead of the log'

issue_log="$executed/logs/issue.log"
grep -q 'claude output issue' "$issue_log" || fail 'lane did not log Claude standard output'
grep -q 'claude warning' "$issue_log" || fail 'lane did not log Claude standard error'
run_recorded "$executed" issue || fail 'second lane run failed'
[[ "$(grep -c 'claude output issue' "$issue_log")" -eq 2 ]] || fail 'lane log was not appended'
[[ -z "$(find "$executed/logs" -prune \( -perm -0040 -o -perm -0004 -o -perm -0020 -o -perm -0002 \) -print)" ]] || fail 'lane log directory is not private'

run_recorded "$executed" ci || fail 'ci lane failed'
[[ "$(cat "$record/lane")" == 'ci' ]] || fail 'ci lane exported the wrong lane'
[[ "$(tail -n 1 "$record/stdin")" == 'CI LANE PROMPT' ]] || fail 'ci lane did not use its prompt'
grep -q 'claude output ci' "$executed/logs/ci.log" || fail 'ci lane did not use its own log'

if FAKE_CLAUDE_RC=3 run_recorded "$executed" issue; then
  fail 'lane hid a Claude failure'
else
  [[ $? -eq 3 ]] || fail 'lane did not propagate the Claude exit code'
fi
[[ ! -e "$executed/lanes.lock" ]] || fail 'lane left its lock behind after a failure'

sleep 30 &
holder=$!
mkdir "$executed/lanes.lock"
printf '%s\n' "$holder" > "$executed/lanes.lock/pid"
rm -f "$record/args"
run_recorded "$executed" ci > "$test_root/out" 2>&1 || fail 'lane failed while another lane held the lock'
[[ ! -e "$record/args" ]] || fail 'lane ran Claude while another lane held the lock'
[[ ! -s "$test_root/out" ]] || fail 'lane was not silent while the lock was held'
kill "$holder"
wait "$holder" 2>/dev/null || true

run_recorded "$executed" ci || fail 'lane did not recover a stale lock'
[[ -e "$record/args" ]] || fail 'lane skipped Claude after the lock holder exited'
[[ ! -e "$executed/lanes.lock" ]] || fail 'lane did not release the recovered lock'

lanes_dir="$repo_root/lanes"
deny_rules="$lanes_dir/deny.json"
[[ -f "$deny_rules" ]] || fail "expected versioned deny rules: $deny_rules"
python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$deny_rules" 2>/dev/null || fail 'deny rules are not valid JSON'
for rule in \
  'Bash(*cdk deploy*)' 'Bash(*cdk destroy*)' 'Bash(*db:migrate:deploy*)' 'Bash(*gh api*dispatches*)' \
  'Bash(*gh pr merge*)' 'Bash(*gh workflow enable*)' 'Bash(*gh workflow run*)' 'Bash(*git push*main*)' \
  'Bash(*prisma migrate deploy*)' 'Bash(*release:api*)' 'Bash(aws *attach*)' 'Bash(aws *create*)' \
  'Bash(aws *delete*)' 'Bash(aws *deploy*)' 'Bash(aws *detach*)' 'Bash(aws *invoke*)' 'Bash(aws *modify*)' \
  'Bash(aws *put*)' 'Bash(aws *remove*)' 'Bash(aws *set-*)' 'Bash(aws *start*)' 'Bash(aws *stop*)' \
  'Bash(aws *tag*)' 'Bash(aws *terminate*)' 'Bash(aws *update*)' 'Bash(aws *upload*)' 'Bash(aws s3 cp*)' \
  'Bash(aws s3 mv*)' 'Bash(aws s3 rm*)' 'Bash(aws s3 sync*)' 'Bash(gh pr merge*)' 'Bash(gh repo delete*)' \
  'Bash(git push --force*)' 'Bash(git push -f*)' 'Bash(git push origin main*)' 'Bash(git reset --hard*)' \
  'Bash(sudo *)'; do
  python3 -I -c 'import json, sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1]))["permissions"]["deny"])' \
    "$deny_rules" "$rule" || fail "deny rules lost: $rule"
done

assert_lane_prompt() {
  local prompt="$lanes_dir/$1.md"
  shift
  [[ -f "$prompt" ]] || fail "expected lane prompt: $prompt"
  grep -qi 'lane mode' "$prompt" || fail "$prompt does not declare lane mode"
  grep -qF 'sdlc/lane-mode.md' "$prompt" || fail "$prompt does not apply sdlc/lane-mode.md"
  grep -qF '<!-- claude-agent:' "$prompt" || fail "$prompt does not define comment markers"
  if grep -Eq '/home/|/Users/|pastor-ia|gustavodsf' "$prompt"; then
    fail "$prompt is not generic"
  fi
  for skill in "$@"; do
    grep -qF "$skill" "$prompt" || fail "$prompt does not delegate to $skill"
  done
}

assert_lane_prompt issue sdlc-project-context sdlc-plan sdlc-review sdlc-qa sdlc-evidence sdlc-pr
assert_lane_prompt ci sdlc-pr sdlc-review
for gate in 'aprovado' 'aprovado: 1, 3' 'evidence_branch'; do
  grep -qF "$gate" "$lanes_dir/issue.md" || fail "issue lane prompt does not cover: $gate"
done

for rule in 'isCrossRepository' 'headRepositoryOwner' 'never check out, install, build, test or run'; do
  grep -qF "$rule" "$lanes_dir/ci.md" || fail "ci lane prompt does not restrict untrusted pull requests: $rule"
done
for prompt in issue ci; do
  for rule in 'A marker comment counts only when' 'userContentEdits' 'edited by anyone other than'; do
    grep -qF "$rule" "$lanes_dir/$prompt.md" || fail "$prompt lane prompt does not guard comment trust: $rule"
  done
done

printf 'PASS: lane behavior\n'
