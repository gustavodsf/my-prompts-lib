#!/usr/bin/env bash

set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_dir="${HOME}/.claude"
codex_dir="${HOME}/.codex"
replace=0
dry_run=0
local_mode=0
track_url=""
track_root="${XDG_DATA_HOME:-${HOME}/.local/share}/apolo-sdlc/projects"
git_bin="${GIT_BIN:-git}"
cron_bin="${CRONTAB_BIN:-crontab}"

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--local | --track GITHUB_URL] [options]

Options:
  --local             Link the shared configuration into Claude and Codex.
  --track GITHUB_URL  Link local configuration, clone the GitHub project, and add a
                      15-minute read-only monitor cron entry.
  --source PATH       Source clone to link from.
  --claude-dir PATH   Claude configuration directory.
  --codex-dir PATH    Codex configuration directory.
  --track-root PATH   Directory used for clones and monitor logs with --track.
  --git-bin PATH      Git executable used to clone with --track.
  --cron-bin PATH     Crontab executable used to schedule with --track.
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

validate_github_url() {
  local url="$1"

  if [[ "$url" =~ ^https://github\.com/([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9][A-Za-z0-9._-]*)(\.git)?$ ]]; then
    track_owner="${BASH_REMATCH[1]}"
    track_repository="${BASH_REMATCH[2]}"
    track_repository="${track_repository%.git}"
    return 0
  fi

  fail "track URL must be an HTTPS GitHub repository URL: $url"
}

normalize_github_remote() {
  local remote_url="$1"
  local remote_owner
  local remote_repository

  if [[ "$remote_url" =~ ^(https://github\.com/|git@github\.com:)([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9][A-Za-z0-9._-]*)(\.git)?$ ]]; then
    remote_owner="${BASH_REMATCH[2]}"
    remote_repository="${BASH_REMATCH[3]}"
    remote_repository="${remote_repository%.git}"
    printf 'https://github.com/%s/%s\n' "$remote_owner" "$remote_repository"
    return 0
  fi

  return 1
}

verify_tracking_origin() {
  local repository_dir="$1"
  local remote_url
  local normalized_remote
  local expected_remote="https://github.com/${track_owner}/${track_repository}"

  remote_url="$("$git_bin" -C "$repository_dir" remote get-url origin)" || fail "tracked repository has no origin remote: $repository_dir"
  normalized_remote="$(normalize_github_remote "$remote_url")" || fail "tracked repository origin is not a GitHub repository: $repository_dir"
  [[ "$normalized_remote" == "$expected_remote" ]] || fail "tracked repository origin does not match requested URL: $repository_dir"
}

quote_for_shell() {
  printf '%q' "$1"
}

schedule_tracking() {
  local repository_dir="$1"
  local log_dir="$track_root/logs"
  local log_file="$log_dir/${track_owner}-${track_repository}.log"
  local marker="# apolo-sdlc-track:${track_owner}/${track_repository}"
  local cron_file
  local cron_error
  local monitor_path="$source_dir/scripts/monitor.sh"
  local cron_line

  [[ -x "$monitor_path" ]] || fail "monitor is not executable: $monitor_path"

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would add or update 15-minute read-only monitor for %s/%s\n' "$track_owner" "$track_repository"
    return 0
  fi

  mkdir -p "$log_dir" || fail "could not create monitor log directory: $log_dir"
  cron_file="$(mktemp "${TMPDIR:-/tmp}/apolo-sdlc-cron.XXXXXX")" || fail 'could not create temporary cron file'
  cron_error="${cron_file}.err"
  trap 'rm -f -- "$cron_file" "$cron_error"' RETURN

  if ! "$cron_bin" -l >"$cron_file" 2>"$cron_error"; then
    if ! grep -Eiq 'no crontab' "$cron_error"; then
      fail "could not read crontab using $cron_bin"
    fi
    : >"$cron_file"
  fi

  cron_line="*/15 * * * * $(quote_for_shell "$monitor_path") --repo $(quote_for_shell "$repository_dir") >> $(quote_for_shell "$log_file") 2>&1 $marker"
  awk -v marker="$marker" 'index($0, marker) == 0 { print }' "$cron_file" >"${cron_file}.next" || fail 'could not prepare crontab update'
  printf '%s\n' "$cron_line" >>"${cron_file}.next"
  mv -- "${cron_file}.next" "$cron_file" || fail 'could not prepare crontab update'
  "$cron_bin" "$cron_file" || fail "could not install crontab using $cron_bin"
  trap - RETURN
  rm -f -- "$cron_file" "$cron_error"
  printf 'Scheduled 15-minute read-only monitor for %s/%s\n' "$track_owner" "$track_repository"
}

prepare_tracking() {
  local repository_dir="$track_root/${track_owner}/${track_repository}"

  if [[ -e "$repository_dir" || -L "$repository_dir" ]]; then
    [[ -d "$repository_dir" && ! -L "$repository_dir" ]] || fail "tracked repository path is not a directory: $repository_dir"
    "$git_bin" -C "$repository_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "tracked repository is not a Git worktree: $repository_dir"
    verify_tracking_origin "$repository_dir"
  elif [[ "$dry_run" -eq 1 ]]; then
    printf 'Would clone %s to %s\n' "$track_url" "$repository_dir"
  else
    mkdir -p "$track_root" || fail "could not create track root: $track_root"
    "$git_bin" clone "$track_url" "$repository_dir" || fail "could not clone tracked repository: $track_url"
    printf 'Cloned %s to %s\n' "$track_url" "$repository_dir"
    verify_tracking_origin "$repository_dir"
  fi

  schedule_tracking "$repository_dir"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      require_value "$1" "${2:-}"
      source_dir="$2"
      shift 2
      ;;
    --local)
      [[ -z "$track_url" ]] || fail '--local cannot be combined with --track'
      local_mode=1
      shift
      ;;
    --track)
      require_value "$1" "${2:-}"
      [[ "$local_mode" -eq 0 && -z "$track_url" ]] || fail '--track cannot be combined with another mode'
      track_url="$2"
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
    --track-root)
      require_value "$1" "${2:-}"
      track_root="$2"
      shift 2
      ;;
    --git-bin)
      require_value "$1" "${2:-}"
      git_bin="$2"
      shift 2
      ;;
    --cron-bin)
      require_value "$1" "${2:-}"
      cron_bin="$2"
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
if [[ -n "$track_url" ]]; then
  validate_github_url "$track_url"
  track_root="$(canonicalize_directory "$track_root")"
  [[ "$track_root" != "/" ]] || fail 'unsafe track root'
fi

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

for index in "${!targets[@]}"; do
  target="${targets[$index]}"
  source_path="${target_sources[$index]}"
  if [[ -L "$target" ]]; then
    if [[ -n "$track_url" && "$(readlink "$target")" == "$source_path" ]]; then
      continue
    fi
    fail "refusing to replace existing symbolic link: $target"
  fi
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

  if [[ -L "$target" && -n "$track_url" && "$(readlink "$target")" == "$source_path" ]]; then
    printf 'Reusing shared link %s\n' "$target"
    continue
  fi

  if [[ -e "$target" ]]; then
    if ! backup_target "$target"; then
      if ! rollback_installation; then
        fail "could not back up managed target and rollback was incomplete: $target"
      fi
      fail "could not back up managed target: $target"
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would link %s to %s\n' "$target" "$source_path"
  else
    if ! ln -s "$source_path" "$target"; then
      if ! rollback_installation; then
        fail "could not link managed target and rollback was incomplete: $target"
      fi
      fail "could not link managed target: $target"
    fi
    created_targets+=("$target")
    printf 'Linked %s to %s\n' "$target" "$source_path"
  fi
done

if [[ -n "$track_url" ]]; then
  prepare_tracking
fi
