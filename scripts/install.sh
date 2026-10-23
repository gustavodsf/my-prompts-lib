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

canonicalize_directory() {
  local requested="$1"
  local candidate
  local base
  local logical_path
  local segment
  local suffix_path=""

  [[ -n "$requested" ]] || fail 'unsafe configuration directory'
  [[ "$requested" = /* ]] || requested="$PWD/$requested"
  candidate="$requested"
  [[ ! -L "$candidate" ]] || fail "configuration directory must not be a symbolic link: $1"
  if [[ -e "$candidate" ]]; then
    logical_path="$(cd -L "$candidate" && pwd -L)"
    [[ "$logical_path" != "/" ]] || fail 'unsafe configuration directory'
  fi

  while [[ ! -e "$candidate" ]]; do
    segment="$(basename "$candidate")"
    [[ "$segment" != '.' && "$segment" != '/' ]] || fail "could not canonicalize configuration directory: $1"
    suffix_path="/$segment$suffix_path"
    candidate="$(dirname "$candidate")"
  done

  [[ -d "$candidate" && ! -L "$candidate" ]] || fail "configuration directory is not a directory: $1"
  base="$(cd -P "$candidate" && pwd -P)"
  printf '%s%s\n' "$base" "$suffix_path"
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
source_dir="$(cd -P "$source_dir" && pwd -P)"
claude_dir="$(canonicalize_directory "$claude_dir")"
codex_dir="$(canonicalize_directory "$codex_dir")"

for directory in "$claude_dir" "$codex_dir"; do
  [[ "$directory" != "/" ]] || fail 'unsafe configuration directory'
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

declare -a created_targets=()
declare -a backed_targets=()
declare -a backup_paths=()
declare -a created_directories=()

rollback_installation() {
  local index
  local target
  local backup
  local rollback_failed=0

  for ((index = ${#created_targets[@]} - 1; index >= 0; index--)); do
    target="${created_targets[$index]}"
    if [[ -L "$target" ]]; then
      rm -- "$target" || rollback_failed=1
    else
      rollback_failed=1
    fi
  done

  for ((index = ${#backed_targets[@]} - 1; index >= 0; index--)); do
    target="${backed_targets[$index]}"
    backup="${backup_paths[$index]}"
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      mv -- "$backup" "$target" || rollback_failed=1
    else
      rollback_failed=1
    fi
  done

  for ((index = ${#created_directories[@]} - 1; index >= 0; index--)); do
    rmdir -- "${created_directories[$index]}" 2>/dev/null || true
  done

  [[ "$rollback_failed" -eq 0 ]]
}

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
    mv -- "$target" "$backup" || return 1
    backed_targets+=("$target")
    backup_paths+=("$backup")
    printf 'Backed up %s to %s\n' "$target" "$backup"
  fi
}

for directory in "$claude_dir" "$codex_dir"; do
  if [[ "$dry_run" -eq 1 ]]; then
    [[ -d "$directory" ]] || printf 'Would create directory %s\n' "$directory"
  else
    if [[ ! -d "$directory" ]]; then
      mkdir -p "$directory" || fail "could not create configuration directory: $directory"
      created_directories+=("$directory")
    fi
  fi
done

for index in "${!targets[@]}"; do
  target="${targets[$index]}"
  source_path="${target_sources[$index]}"

  if [[ -e "$target" ]]; then
    if ! backup_target "$target"; then
      rollback_installation || true
      fail "could not back up managed target: $target"
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would link %s to %s\n' "$target" "$source_path"
  else
    if ! ln -s "$source_path" "$target"; then
      rollback_installation || true
      fail "could not link managed target: $target"
    fi
    created_targets+=("$target")
    printf 'Linked %s to %s\n' "$target" "$source_path"
  fi
done
