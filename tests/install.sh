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

[[ -x "$installer" ]] || fail "expected executable installer: $installer"

source_root="$test_root/source"
claude_dir="$test_root/claude"
codex_dir="$test_root/codex"
blocked_claude_dir="$test_root/blocked-claude"
blocked_codex_dir="$test_root/blocked-codex"
mkdir -p "$source_root/sdlc" "$source_root/commands" "$source_root/skills/example" "$claude_dir/commands" "$codex_dir/skills" "$blocked_claude_dir" "$blocked_codex_dir"
printf 'claude rules\n' > "$source_root/CLAUDE.md"
printf 'codex rules\n' > "$source_root/AGENTS.md"
printf 'error catalog\n' > "$source_root/sdlc/error.md"
printf 'command\n' > "$source_root/commands/context.md"
printf 'skill\n' > "$source_root/skills/example/SKILL.md"
printf 'legacy claude rules\n' > "$claude_dir/CLAUDE.md"
printf 'legacy command\n' > "$claude_dir/commands/legacy.md"
printf 'legacy codex rules\n' > "$codex_dir/AGENTS.md"
printf 'legacy skill\n' > "$codex_dir/skills/legacy.md"

printf 'protected claude rules\n' > "$blocked_claude_dir/CLAUDE.md"

if "$installer" --source "$source_root" --claude-dir "$blocked_claude_dir" --codex-dir "$blocked_codex_dir"; then
  fail 'expected installer to require --replace for an existing target'
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

printf 'PASS: installer behavior\n'
