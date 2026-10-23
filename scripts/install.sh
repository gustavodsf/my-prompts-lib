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
runner_root="${XDG_DATA_HOME:-${HOME}/.local/share}/apolo-sdlc/runners"
git_bin="${GIT_BIN:-git}"
cron_bin="${CRONTAB_BIN:-crontab}"
track_error=""
track_created_repository=""
track_created_dirs=()
track_created_runner=""
track_previous_runner=""
new_dirs=()

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
  --track-root PATH   Directory used for tracked clones with --track.
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

track_fail() {
  track_error="$1"
  return 1
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

parse_github_repository() {
  local url="$1"
  local allow_ssh="$2"
  local prefix='https://github\.com/'
  local pattern

  [[ "$allow_ssh" -eq 0 ]] || prefix='(https://github\.com/|git@github\.com:|ssh://git@github\.com/)'
  pattern="^${prefix}([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9][A-Za-z0-9._-]*)$"
  url="${url%.git}"
  [[ "$url" =~ $pattern ]] || return 1
  printf '%s/%s\n' "${BASH_REMATCH[${#BASH_REMATCH[@]} - 2]}" "${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}"
}

validate_github_url() {
  local url="$1"
  local repository

  repository="$(parse_github_repository "$url" 0)" || fail "track URL must be an HTTPS GitHub repository URL: $url"
  track_owner="${repository%%/*}"
  track_repository="${repository#*/}"
}

# Reads the configured URL because `git remote get-url` applies insteadOf rewrites.
verify_tracking_origin() {
  local repository_dir="$1"
  local remote_url
  local remote_repository

  remote_url="$("$git_bin" -C "$repository_dir" config --get remote.origin.url)" || { track_fail "tracked repository has no origin remote: $repository_dir"; return 1; }
  remote_repository="$(parse_github_repository "$remote_url" 1)" || { track_fail "tracked repository origin is not a GitHub repository: $repository_dir"; return 1; }
  [[ "$remote_repository" == "${track_owner}/${track_repository}" ]] || { track_fail "tracked repository origin does not match requested URL: $repository_dir"; return 1; }
}

validate_cron_path() {
  [[ "$1" != *%* && ! "$1" =~ [^[:print:]] ]] || fail "path cannot be scheduled safely by cron: $1"
}

# Creates missing directories outermost first and records them in new_dirs for rollback.
create_directory_tree() {
  local mode="$1"
  local directory="$2"
  local -a missing=()

  new_dirs=()
  while [[ ! -e "$directory" && ! -L "$directory" ]]; do
    missing=("$directory" ${missing[@]+"${missing[@]}"})
    directory="$(dirname "$directory")"
  done
  for directory in ${missing[@]+"${missing[@]}"}; do
    mkdir ${mode:+-m "$mode"} -- "$directory" || return 1
    new_dirs+=("$directory")
  done
}

remove_directories() {
  local index
  local removal_failed=0
  local -a directories=("$@")

  for ((index = ${#directories[@]} - 1; index >= 0; index--)); do
    rmdir -- "${directories[$index]}" 2>/dev/null || removal_failed=1
  done
  [[ "$removal_failed" -eq 0 ]]
}

is_private_directory() {
  local directory="$1"

  [[ -d "$directory" && ! -L "$directory" && -O "$directory" ]] || return 1
  [[ -z "$(find "$directory" -prune \( -perm -0020 -o -perm -0002 \) -print)" ]]
}

# Another user must not be able to rename entries in any ancestor; root-owned or sticky shared directories qualify.
has_trusted_ancestors() {
  local directory

  directory="$(dirname "$1")"
  while [[ ! -e "$directory" && ! -L "$directory" ]]; do
    directory="$(dirname "$directory")"
  done
  while true; do
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    [[ -O "$directory" || -n "$(find "$directory" -prune -user 0 -print)" ]] || return 1
    [[ -z "$(find "$directory" -prune \( -perm -0020 -o -perm -0002 \) ! -perm -1000 -print)" ]] || return 1
    [[ "$directory" != "/" ]] || return 0
    directory="$(dirname "$directory")"
  done
}

require_private_directories() {
  local directory

  for directory in "$@"; do
    is_private_directory "$directory" || { track_fail "tracked directory must be a private directory owned by the current user: $directory"; return 1; }
  done
}

create_tracking_tree() {
  local status=0

  create_directory_tree 700 "$1" || status=1
  track_created_dirs+=(${new_dirs[@]+"${new_dirs[@]}"})
  return "$status"
}

quote_for_shell() {
  printf '%q' "$1"
}

# The schedule runs a private copy so later changes to the configuration clone require a supervised reinstall.
install_runner() {
  local runner_path="$1"
  local runner_dir
  local monitor_path="$source_dir/scripts/monitor.sh"
  local directory
  local staged_runner

  runner_dir="$(dirname "$runner_path")"
  [[ -x "$monitor_path" ]] || { track_fail "monitor is not executable: $monitor_path"; return 1; }

  create_tracking_tree "$runner_dir" || { track_fail "could not create runner directory: $runner_dir"; return 1; }
  has_trusted_ancestors "$runner_root" || { track_fail "runner root has an ancestor writable by other users: $runner_root"; return 1; }
  for directory in "$runner_root" "$(dirname "$runner_dir")" "$runner_dir"; do
    is_private_directory "$directory" || { track_fail "runner directory must be a private directory owned by the current user: $directory"; return 1; }
  done

  if [[ -e "$runner_path" || -L "$runner_path" ]]; then
    [[ -f "$runner_path" && ! -L "$runner_path" ]] || { track_fail "runner path is not a regular file: $runner_path"; return 1; }
    track_previous_runner="$(mktemp "$runner_dir/.monitor.previous.XXXXXX")" || { track_previous_runner=""; track_fail "could not preserve existing monitor runner: $runner_path"; return 1; }
    if ! cp -p -- "$runner_path" "$track_previous_runner"; then
      rm -f -- "$track_previous_runner"
      track_previous_runner=""
      track_fail "could not preserve existing monitor runner: $runner_path"
      return 1
    fi
  else
    track_created_runner="$runner_path"
  fi

  staged_runner="$(mktemp "$runner_dir/.monitor.XXXXXX")" || { track_fail "could not stage monitor runner in $runner_dir"; return 1; }
  if ! cp -- "$monitor_path" "$staged_runner" || ! chmod 700 "$staged_runner" || ! mv -f -- "$staged_runner" "$runner_path"; then
    rm -f -- "$staged_runner"
    track_fail "could not install monitor runner: $runner_path"
    return 1
  fi
  printf 'Installed managed monitor runner at %s\n' "$runner_path"
}

write_crontab() {
  local work_dir="$1"
  local marker="$2"
  local cron_line="$3"

  if ! "$cron_bin" -l >"$work_dir/current" 2>"$work_dir/error"; then
    grep -Eiq 'no crontab' "$work_dir/error" || { track_fail "could not read crontab using $cron_bin"; return 1; }
    : >"$work_dir/current"
  fi
  awk -v marker="$marker" '{ start = length($0) - length(marker) + 1 } start < 1 || substr($0, start) != marker { print }' \
    "$work_dir/current" >"$work_dir/next" || { track_fail 'could not prepare crontab update'; return 1; }
  printf '%s\n' "$cron_line" >>"$work_dir/next" || { track_fail 'could not prepare crontab update'; return 1; }
  "$cron_bin" "$work_dir/next" || { track_fail "could not install crontab using $cron_bin"; return 1; }
}

schedule_tracking() {
  local repository_dir="$1"
  local marker="# apolo-sdlc-track:${track_owner}/${track_repository}"
  local runner_path="$runner_root/${track_owner}/${track_repository}/monitor.sh"
  local error_log="$runner_root/${track_owner}/${track_repository}/last-error.log"
  local work_dir
  local cron_line

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'Would install managed monitor runner at %s\n' "$runner_path"
    printf 'Would add or update 15-minute read-only monitor for %s/%s\n' "$track_owner" "$track_repository"
    return 0
  fi

  install_runner "$runner_path" || return 1

  # Stdout is discarded; stderr is truncated each run so only the latest failure is kept.
  cron_line="*/15 * * * * $(quote_for_shell "$runner_path") --scheduled --repo $(quote_for_shell "$repository_dir") >/dev/null 2> $(quote_for_shell "$error_log") $marker"
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/apolo-sdlc-cron.XXXXXX")" || { track_fail 'could not create temporary cron directory'; return 1; }
  if ! write_crontab "$work_dir" "$marker" "$cron_line"; then
    rm -rf -- "$work_dir"
    return 1
  fi
  rm -rf -- "$work_dir"
  [[ -z "$track_previous_runner" ]] || rm -f -- "$track_previous_runner"
  track_previous_runner=""
  printf 'Scheduled 15-minute read-only monitor for %s/%s\n' "$track_owner" "$track_repository"
}

prepare_tracking() {
  local repository_dir="$track_root/${track_owner}/${track_repository}"
  local owner_dir="$track_root/${track_owner}"

  has_trusted_ancestors "$track_root" || { track_fail "track root has an ancestor writable by other users: $track_root"; return 1; }
  has_trusted_ancestors "$runner_root" || { track_fail "runner root has an ancestor writable by other users: $runner_root"; return 1; }

  if [[ -e "$repository_dir" || -L "$repository_dir" ]]; then
    [[ -d "$repository_dir" && ! -L "$repository_dir" ]] || { track_fail "tracked repository path is not a directory: $repository_dir"; return 1; }
    require_private_directories "$track_root" "$owner_dir" "$repository_dir" || return 1
    "$git_bin" -C "$repository_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { track_fail "tracked repository is not a Git worktree: $repository_dir"; return 1; }
    verify_tracking_origin "$repository_dir" || return 1
  elif [[ "$dry_run" -eq 1 ]]; then
    printf 'Would clone %s to %s\n' "$track_url" "$repository_dir"
  else
    # Verify after creation so neither the clone nor a rollback rm -rf can follow a path another user controls.
    create_tracking_tree "$owner_dir" || { track_fail "could not create tracked repository directory: $owner_dir"; return 1; }
    has_trusted_ancestors "$owner_dir" || { track_fail "track root has an ancestor writable by other users: $track_root"; return 1; }
    require_private_directories "$track_root" "$owner_dir" || return 1
    track_created_repository="$repository_dir"
    "$git_bin" clone --depth 1 "$track_url" "$repository_dir" || { track_fail "could not clone tracked repository: $track_url"; return 1; }
    chmod 700 "$repository_dir" || { track_fail "could not restrict tracked repository: $repository_dir"; return 1; }
    printf 'Cloned %s to %s\n' "$track_url" "$repository_dir"
    verify_tracking_origin "$repository_dir" || return 1
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
  runner_root="$(canonicalize_directory "$runner_root")"
  [[ "$runner_root" != "/" ]] || fail 'unsafe runner root'
  validate_cron_path "$track_root/${track_owner}/${track_repository}"
  validate_cron_path "$runner_root/${track_owner}/${track_repository}/last-error.log"
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

  remove_directories ${created_directories[@]+"${created_directories[@]}"} || rollback_failed=1

  [[ "$rollback_failed" -eq 0 ]]
}

rollback_tracking() {
  local rollback_failed=0

  if [[ -n "$track_previous_runner" ]]; then
    mv -f -- "$track_previous_runner" "$(dirname "$track_previous_runner")/monitor.sh" || rollback_failed=1
  elif [[ -n "$track_created_runner" && -e "$track_created_runner" ]]; then
    rm -f -- "$track_created_runner" || rollback_failed=1
  fi
  if [[ -n "$track_created_repository" && ( -e "$track_created_repository" || -L "$track_created_repository" ) ]]; then
    rm -rf -- "$track_created_repository" || rollback_failed=1
  fi
  remove_directories ${track_created_dirs[@]+"${track_created_dirs[@]}"} || rollback_failed=1

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
    status=0
    create_directory_tree '' "$directory" || status=1
    created_directories+=(${new_dirs[@]+"${new_dirs[@]}"})
    if [[ "$status" -eq 1 ]]; then
      rollback_installation || true
      fail "could not create configuration directory: $directory"
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
  if ! prepare_tracking; then
    rollback_failed=0
    rollback_tracking || rollback_failed=1
    rollback_installation || rollback_failed=1
    if [[ "$rollback_failed" -eq 1 ]]; then
      fail "tracking setup failed and rollback was incomplete: ${track_error:-unknown tracking error}"
    fi
    fail "tracking setup failed and local configuration was rolled back: ${track_error:-unknown tracking error}"
  fi
fi
