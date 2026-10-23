#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/github-write.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$wrapper" ]] || fail "expected executable wrapper: $wrapper"

repo_dir="$test_root/repository"
state_file="$test_root/authorized.state"
fake_bin="$test_root/bin"
log_file="$test_root/calls.log"
mkdir -p "$repo_dir" "$fake_bin"
git -C "$repo_dir" init -q
git -C "$repo_dir" remote add origin 'https://github.com/acme/repository.git'
git -C "$repo_dir" switch -q -c issue-42-safe-wrapper
repo_dir="$(git -C "$repo_dir" rev-parse --show-toplevel)"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "gh %s\\n" "$*" >> "$GITHUB_WRITE_LOG"' > "$fake_bin/gh"
chmod +x "$fake_bin/gh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$1" == "push" ]]; then' \
  '  printf "git %s\\n" "$*" >> "$GITHUB_WRITE_LOG"' \
  '  exit 0' \
  'fi' \
  'exec /usr/bin/git "$@"' > "$fake_bin/git"
chmod +x "$fake_bin/git"

printf 'version=1\nrepo=%s\nremote=https://github.com/acme/repository.git\nissue=42\nstatus=authorized\n' "$repo_dir" > "$state_file"

run_wrapper() {
  PATH="$fake_bin:$PATH" GITHUB_WRITE_LOG="$log_file" APOLO_AUTHORIZATION_STATE="${APOLO_AUTHORIZATION_STATE:-$state_file}" APOLO_AUTHORIZED_REPO="${APOLO_AUTHORIZED_REPO:-$repo_dir}" APOLO_AUTHORIZED_REMOTE="${APOLO_AUTHORIZED_REMOTE:-https://github.com/acme/repository.git}" APOLO_AUTHORIZED_ISSUE="${APOLO_AUTHORIZED_ISSUE:-42}" "$wrapper" "$@"
}

(
  cd "$repo_dir"
  run_wrapper comment 'Progress: focused tests passed.'
)
grep -F 'gh issue comment 42 --body Progress: focused tests passed.' "$log_file" >/dev/null || fail 'wrapper did not comment on the authorized issue'

(
  cd "$repo_dir"
  run_wrapper push
  run_wrapper create-pr 'Issue 42 implementation' 'Validated with synthetic data.'
)
grep -F 'git push --set-upstream origin issue-42-safe-wrapper' "$log_file" >/dev/null || fail 'wrapper did not push the authorized branch'
grep -F 'gh pr create --head issue-42-safe-wrapper --title Issue 42 implementation' "$log_file" >/dev/null || fail 'wrapper did not create a pull request for the authorized branch'

if (
  cd "$repo_dir"
  APOLO_AUTHORIZED_ISSUE=7 run_wrapper comment 'wrong issue'
); then
  fail 'wrapper accepted a different authorized issue from the caller'
fi

printf 'PASS: authorized GitHub write wrapper\n'
