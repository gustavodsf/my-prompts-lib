#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/install.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_link() {
  local target="$1"
  local expected="$2"

  [[ -L "$target" ]] || fail "expected symbolic link: $target"
  [[ "$(readlink "$target")" == "$expected" ]] || fail "unexpected link target: $target"
}

assert_backup() {
  local directory="$1"
  local name="$2"

  find "$directory" -maxdepth 1 -name "${name}-old-*" -print -quit | grep -q . || fail "expected backup for $name"
}

assert_file_content() {
  local path="$1"
  local expected="$2"

  [[ ! -L "$path" && -f "$path" ]] || fail "expected regular file: $path"
  [[ "$(<"$path")" == "$expected" ]] || fail "unexpected file content: $path"
}

[[ -x "$installer" ]] || fail "expected executable installer: $installer"

source_root="$test_root/source"
claude_dir="$test_root/claude"
codex_dir="$test_root/codex"
blocked_claude_dir="$test_root/blocked-claude"
blocked_codex_dir="$test_root/blocked-codex"
mkdir -p "$source_root/sdlc" "$source_root/commands" "$source_root/skills/example" "$source_root/scripts" "$claude_dir/commands" "$codex_dir/skills" "$blocked_claude_dir" "$blocked_codex_dir"
source_root="$(cd -P "$source_root" && pwd -P)"
printf 'claude rules\n' > "$source_root/CLAUDE.md"
printf 'codex rules\n' > "$source_root/AGENTS.md"
printf 'error catalog\n' > "$source_root/sdlc/error.md"
printf 'command\n' > "$source_root/commands/context.md"
printf 'skill\n' > "$source_root/skills/example/SKILL.md"
printf '#!/usr/bin/env bash\n' > "$source_root/scripts/monitor.sh"
chmod +x "$source_root/scripts/monitor.sh"
printf 'legacy claude rules\n' > "$claude_dir/CLAUDE.md"
printf 'legacy command\n' > "$claude_dir/commands/legacy.md"
printf 'legacy codex rules\n' > "$codex_dir/AGENTS.md"
printf 'legacy skill\n' > "$codex_dir/skills/legacy.md"

printf 'protected claude rules\n' > "$blocked_claude_dir/CLAUDE.md"

if "$installer" --source "$source_root" --claude-dir "$blocked_claude_dir" --codex-dir "$blocked_codex_dir"; then
  fail 'expected installer to require --replace for an existing target'
fi

if "$installer" --source "$source_root" --claude-dir /tmp/.. --codex-dir "$blocked_codex_dir" --replace --dry-run; then
  fail 'installer accepted a configuration directory that resolves to the filesystem root'
fi

[[ ! -L "$blocked_claude_dir/CLAUDE.md" ]] || fail 'installer replaced a target without --replace'
[[ "$(<"$blocked_claude_dir/CLAUDE.md")" == 'protected claude rules' ]] || fail 'installer changed a target without --replace'

"$installer" --source "$source_root" --claude-dir "$claude_dir" --codex-dir "$codex_dir" --replace

assert_link "$claude_dir/CLAUDE.md" "$source_root/CLAUDE.md"
assert_link "$claude_dir/sdlc" "$source_root/sdlc"
assert_link "$claude_dir/commands" "$source_root/commands"
assert_link "$claude_dir/skills" "$source_root/skills"
assert_link "$codex_dir/AGENTS.md" "$source_root/AGENTS.md"
assert_link "$codex_dir/sdlc" "$source_root/sdlc"
assert_link "$codex_dir/commands" "$source_root/commands"
assert_link "$codex_dir/skills" "$source_root/skills"
assert_backup "$claude_dir" 'CLAUDE.md'
assert_backup "$claude_dir" 'commands'
assert_backup "$codex_dir" 'AGENTS.md'
assert_backup "$codex_dir" 'skills'

linked_claude_dir="$test_root/linked-claude"
linked_codex_dir="$test_root/linked-codex"
mkdir -p "$linked_claude_dir" "$linked_codex_dir"
ln -s "$source_root/CLAUDE.md" "$linked_claude_dir/CLAUDE.md"

if "$installer" --source "$source_root" --claude-dir "$linked_claude_dir" --codex-dir "$linked_codex_dir" --replace; then
  fail 'expected installer to reject an existing symbolic link'
fi

assert_link "$linked_claude_dir/CLAUDE.md" "$source_root/CLAUDE.md"

dry_claude_dir="$test_root/dry-claude"
dry_codex_dir="$test_root/dry-codex"
mkdir -p "$dry_claude_dir" "$dry_codex_dir"
printf 'legacy claude rules\n' > "$dry_claude_dir/CLAUDE.md"
printf 'legacy codex rules\n' > "$dry_codex_dir/AGENTS.md"

"$installer" --source "$source_root" --claude-dir "$dry_claude_dir" --codex-dir "$dry_codex_dir" --replace --dry-run

[[ ! -L "$dry_claude_dir/CLAUDE.md" ]] || fail 'dry run changed Claude configuration'
[[ ! -L "$dry_codex_dir/AGENTS.md" ]] || fail 'dry run changed Codex configuration'
[[ ! -e "$dry_claude_dir"/CLAUDE.md-old-* ]] || fail 'dry run created a Claude backup'
[[ ! -e "$dry_codex_dir"/AGENTS.md-old-* ]] || fail 'dry run created a Codex backup'

transaction_claude_dir="$test_root/transaction-claude"
transaction_codex_dir="$test_root/transaction-codex"
fake_bin="$test_root/fake-bin"
link_counter="$test_root/link-counter"
mkdir -p "$transaction_claude_dir/sdlc" "$transaction_claude_dir/commands" "$transaction_claude_dir/skills" "$transaction_codex_dir/sdlc" "$transaction_codex_dir/commands" "$transaction_codex_dir/skills" "$fake_bin"
printf 'legacy transactional claude\n' > "$transaction_claude_dir/CLAUDE.md"
printf 'legacy transactional codex\n' > "$transaction_codex_dir/AGENTS.md"
printf 'legacy transactional claude sdlc\n' > "$transaction_claude_dir/sdlc/legacy.md"
printf 'legacy transactional claude commands\n' > "$transaction_claude_dir/commands/legacy.md"
printf 'legacy transactional claude skills\n' > "$transaction_claude_dir/skills/legacy.md"
printf 'legacy transactional codex sdlc\n' > "$transaction_codex_dir/sdlc/legacy.md"
printf 'legacy transactional codex commands\n' > "$transaction_codex_dir/commands/legacy.md"
printf 'legacy transactional codex skills\n' > "$transaction_codex_dir/skills/legacy.md"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'count=0' \
  '[[ -f "$INSTALL_LINK_COUNTER" ]] && count="$(<"$INSTALL_LINK_COUNTER")"' \
  'count=$((count + 1))' \
  'printf "%s\\n" "$count" > "$INSTALL_LINK_COUNTER"' \
  '[[ "$count" != "$INSTALL_FAIL_LINK_AT" ]] || exit 1' \
  'exec /bin/ln "$@"' > "$fake_bin/ln"
chmod +x "$fake_bin/ln"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  '[[ "${INSTALL_FAIL_REMOVE:-0}" != "1" ]] || exit 1' \
  'exec /bin/rm "$@"' > "$fake_bin/rm"
chmod +x "$fake_bin/rm"

if PATH="$fake_bin:$PATH" INSTALL_LINK_COUNTER="$link_counter" INSTALL_FAIL_LINK_AT=5 "$installer" --source "$source_root" --claude-dir "$transaction_claude_dir" --codex-dir "$transaction_codex_dir" --replace; then
  fail 'installer did not fail when link creation failed mid-transaction'
fi

assert_file_content "$transaction_claude_dir/CLAUDE.md" 'legacy transactional claude'
assert_file_content "$transaction_codex_dir/AGENTS.md" 'legacy transactional codex'
assert_file_content "$transaction_claude_dir/sdlc/legacy.md" 'legacy transactional claude sdlc'
assert_file_content "$transaction_claude_dir/commands/legacy.md" 'legacy transactional claude commands'
assert_file_content "$transaction_claude_dir/skills/legacy.md" 'legacy transactional claude skills'
assert_file_content "$transaction_codex_dir/sdlc/legacy.md" 'legacy transactional codex sdlc'
assert_file_content "$transaction_codex_dir/commands/legacy.md" 'legacy transactional codex commands'
assert_file_content "$transaction_codex_dir/skills/legacy.md" 'legacy transactional codex skills'
if find "$transaction_claude_dir" "$transaction_codex_dir" -maxdepth 1 -name '*-old-*' -print -quit | grep -q .; then
  fail 'installer left backup artifacts after rollback'
fi

: > "$link_counter"
if PATH="$fake_bin:$PATH" INSTALL_LINK_COUNTER="$link_counter" INSTALL_FAIL_LINK_AT=5 INSTALL_FAIL_REMOVE=1 "$installer" --source "$source_root" --claude-dir "$transaction_claude_dir" --codex-dir "$transaction_codex_dir" --replace > "$test_root/rollback-failure.out" 2>&1; then
  fail 'installer accepted an incomplete rollback'
fi
grep -q 'rollback was incomplete' "$test_root/rollback-failure.out" || fail 'installer did not report an incomplete rollback'

local_claude_dir="$test_root/local-claude"
local_codex_dir="$test_root/local-codex"
"$installer" --local --source "$source_root" --claude-dir "$local_claude_dir" --codex-dir "$local_codex_dir"

assert_link "$local_claude_dir/CLAUDE.md" "$source_root/CLAUDE.md"
assert_link "$local_codex_dir/AGENTS.md" "$source_root/AGENTS.md"

track_bin="$test_root/track-bin"
track_root="$(cd -P "$test_root" && pwd -P)/tracked-projects"
track_claude_dir="$test_root/track-claude"
track_codex_dir="$test_root/track-codex"
cron_file="$test_root/crontab"
mkdir -p "$track_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$1" == "clone" ]]; then' \
  '  [[ "${TRACK_FAIL_CLONE:-0}" != "1" ]] || exit 1' \
  '  mkdir -p "$3/.git"' \
  '  printf "%s\\n" "$2" > "$3/.git/origin-url"' \
  '  exit 0' \
  'fi' \
  'if [[ "$1" == "-C" && "$3" == "rev-parse" && "$4" == "--is-inside-work-tree" ]]; then exit 0; fi' \
  'if [[ "$1" == "-C" && "$3" == "remote" && "$4" == "get-url" && "$5" == "origin" ]]; then cat "$2/.git/origin-url"; exit 0; fi' \
  'exit 1' > "$track_bin/git"
chmod +x "$track_bin/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$1" == "-l" ]]; then' \
  '  if [[ -f "$TEST_CRON_FILE" ]]; then cat "$TEST_CRON_FILE"; else echo "no crontab for test" >&2; exit 1; fi' \
  'else' \
  '  cp "$1" "$TEST_CRON_FILE"' \
  'fi' > "$track_bin/crontab"
chmod +x "$track_bin/crontab"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$1" == "-l" ]]; then' \
  '  if [[ -f "$TEST_CRON_FILE" ]]; then cat "$TEST_CRON_FILE"; exit 0; else echo "no crontab for test" >&2; exit 1; fi' \
  'fi' \
  'exit 1' > "$track_bin/failing-crontab"
chmod +x "$track_bin/failing-crontab"

TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/example/demo --source "$source_root" --claude-dir "$track_claude_dir" --codex-dir "$track_codex_dir" --track-root "$track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"

assert_link "$track_claude_dir/CLAUDE.md" "$source_root/CLAUDE.md"
assert_link "$track_codex_dir/AGENTS.md" "$source_root/AGENTS.md"
[[ -d "$track_root/example/demo/.git" ]] || fail 'track mode did not prepare a local clone'
if ! grep -F "$source_root/scripts/monitor.sh --repo $track_root/example/demo" "$cron_file" >/dev/null; then
  sed -n '1,10p' "$cron_file" >&2
  fail 'track mode did not target the cloned repository'
fi
grep -F '# apolo-sdlc-track:example/demo' "$cron_file" >/dev/null || fail 'track mode did not mark its cron entry'
if rg -q 'claude|curl|aws|gh issue comment|git push|gh pr create' "$cron_file"; then
  fail 'track mode added a cron entry with a write or external execution path'
fi

TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/example/demo --source "$source_root" --claude-dir "$track_claude_dir" --codex-dir "$track_codex_dir" --track-root "$track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"
[[ "$(grep -Fc '# apolo-sdlc-track:example/demo' "$cron_file")" == 1 ]] || fail 'track mode duplicated its cron entry'

TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/a-b/c --source "$source_root" --claude-dir "$track_claude_dir" --codex-dir "$track_codex_dir" --track-root "$track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"
TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/a/b-c --source "$source_root" --claude-dir "$track_claude_dir" --codex-dir "$track_codex_dir" --track-root "$track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"
[[ -d "$track_root/a-b/c/.git" && -d "$track_root/a/b-c/.git" ]] || fail 'track mode allowed distinct GitHub repositories to collide'
[[ "$(grep -Fc '# apolo-sdlc-track:a-b/c' "$cron_file")" == 1 ]] || fail 'first collision scenario was not scheduled'
[[ "$(grep -Fc '# apolo-sdlc-track:a/b-c' "$cron_file")" == 1 ]] || fail 'second collision scenario was not scheduled'

mkdir -p "$track_root/mismatch/demo/.git"
printf 'https://github.com/mismatch/other\n' > "$track_root/mismatch/demo/.git/origin-url"
if TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/mismatch/demo --source "$source_root" --claude-dir "$track_claude_dir" --codex-dir "$track_codex_dir" --track-root "$track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"; then
  fail 'track mode accepted a worktree with an incompatible origin'
fi
[[ "$(grep -Fc '# apolo-sdlc-track:mismatch/demo' "$cron_file")" == 0 ]] || fail 'incompatible origin changed the crontab'

if TEST_CRON_FILE="$cron_file" "$installer" --track 'https://github.com/example/demo?token=nope' --source "$source_root" --claude-dir "$test_root/invalid-claude" --codex-dir "$test_root/invalid-codex" --track-root "$test_root/invalid-track" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"; then
  fail 'track mode accepted an unsafe GitHub URL'
fi
[[ ! -e "$test_root/invalid-track" ]] || fail 'invalid track URL created a clone directory'

clone_failure_claude_dir="$test_root/clone-failure-claude"
clone_failure_codex_dir="$test_root/clone-failure-codex"
clone_failure_track_root="$test_root/clone-failure-tracks"
if TRACK_FAIL_CLONE=1 TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/failure/clone --source "$source_root" --claude-dir "$clone_failure_claude_dir" --codex-dir "$clone_failure_codex_dir" --track-root "$clone_failure_track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/crontab"; then
  fail 'track mode accepted a clone failure'
fi
[[ ! -e "$clone_failure_claude_dir" && ! -e "$clone_failure_codex_dir" ]] || fail 'clone failure left local configuration changes'
[[ ! -e "$clone_failure_track_root" ]] || fail 'clone failure left a tracking directory'

cron_failure_claude_dir="$test_root/cron-failure-claude"
cron_failure_codex_dir="$test_root/cron-failure-codex"
cron_failure_track_root="$test_root/cron-failure-tracks"
if TEST_CRON_FILE="$cron_file" "$installer" --track https://github.com/failure/cron --source "$source_root" --claude-dir "$cron_failure_claude_dir" --codex-dir "$cron_failure_codex_dir" --track-root "$cron_failure_track_root" --git-bin "$track_bin/git" --cron-bin "$track_bin/failing-crontab"; then
  fail 'track mode accepted a crontab failure'
fi
[[ ! -e "$cron_failure_claude_dir" && ! -e "$cron_failure_codex_dir" ]] || fail 'crontab failure left local configuration changes'
[[ ! -e "$cron_failure_track_root" ]] || fail 'crontab failure left a tracking directory'

printf 'PASS: installer behavior\n'
