#!/usr/bin/env bash

set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_dir="${HOME}/.claude"
codex_dir="${HOME}/.codex"
replace=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [options]

Options:
  --source PATH       Source clone to link from.
  --claude-dir PATH   Claude configuration directory.
  --codex-dir PATH    Codex configuration directory.
  --replace           Back up existing managed targets before linking.
  --dry-run           Print planned actions without changing files.
  --help              Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_value() {
  [[ $# -eq 2 && -n "$2" ]] || fail "missing value for $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      require_value "$1" "${2:-}"
      source_dir="$2"
      shift 2
      ;;
    --claude-dir)
      require_value "$1" "${2:-}"
      claude_dir="$2"
      shift 2
      ;;
    --codex-dir)
      require_value "$1" "${2:-}"
      codex_dir="$2"
      shift 2
      ;;
    --replace)
      replace=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -d "$source_dir" ]] || fail "source directory does not exist: $source_dir"
source_dir="$(cd "$source_dir" && pwd)"

for directory in "$claude_dir" "$codex_dir"; do
  [[ -n "$directory" && "$directory" != "/" && "$directory" != "." ]] || fail 'unsafe configuration directory'
  [[ ! -L "$directory" ]] || fail "configuration directory must not be a symbolic link: $directory"
  [[ ! -e "$directory" || -d "$directory" ]] || fail "configuration directory is not a directory: $directory"
done

declare -a sources=(
  "$source_dir/CLAUDE.md"
  "$source_dir/AGENTS.md"
  "$source_dir/sdlc"
  "$source_dir/commands"
  "$source_dir/skills"
)

for source_path in "${sources[@]}"; do
  [[ -e "$source_path" ]] || fail "managed source does not exist: $source_path"
done

declare -a target_sources=(
  "$source_dir/CLAUDE.md"
  "$source_dir/sdlc"
  "$source_dir/commands"
  "$source_dir/skills"
  "$source_dir/AGENTS.md"
  "$source_dir/sdlc"
  "$source_dir/commands"
  "$source_dir/skills"
)
declare -a targets=(
  "$claude_dir/CLAUDE.md"
  "$claude_dir/sdlc"
  "$claude_dir/commands"
  "$claude_dir/skills"
  "$codex_dir/AGENTS.md"
  "$codex_dir/sdlc"
  "$codex_dir/commands"
  "$codex_dir/skills"
)

for target in "${targets[@]}"; do
  [[ ! -L "$target" ]] || fail "refusing to replace existing symbolic link: $target"
  [[ ! -e "$target" || "$replace" -eq 1 ]] || fail "managed target exists; rerun with --replace: $target"
done

backup_target() {
  local target="$1"
  local timestamp
  local backup
  local suffix=0

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  backup="${target}-old-${timestamp}"
  while [[ -e "$backup" || -L "$backup" ]]; do
    suffix=$((suffix + 1))
    backup="${target}-old-${timestamp}-${suffix}"
  done

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would back up %s to %s\n' "$target" "$backup"
  else
    mv "$target" "$backup"
    printf 'Backed up %s to %s\n' "$target" "$backup"
  fi
}

for directory in "$claude_dir" "$codex_dir"; do
  if [[ "$dry_run" -eq 1 ]]; then
    [[ -d "$directory" ]] || printf 'Would create directory %s\n' "$directory"
  else
    mkdir -p "$directory"
  fi
done

for index in "${!targets[@]}"; do
  target="${targets[$index]}"
  source_path="${target_sources[$index]}"

  if [[ -e "$target" ]]; then
    backup_target "$target"
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would link %s to %s\n' "$target" "$source_path"
  else
    ln -s "$source_path" "$target"
    printf 'Linked %s to %s\n' "$target" "$source_path"
  fi
done
