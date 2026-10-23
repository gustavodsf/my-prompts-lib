#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(pwd)"
state_file=""
state_root="${XDG_STATE_HOME:-${HOME}/.local/state}/apolo-sdlc"
limit=30
max_limit=50
dry_run=0
authorize_issue=""
clear_authorization=0
repo_remote=""
state_issue=""
state_status=""
state_repo=""
state_remote=""

usage() {
  cat <<'EOF'
Usage: scripts/monitor.sh [options]

Options:
  --authorize ISSUE          Persist one explicitly authorized GitHub issue for this repository.
  --clear-authorization      Remove this repository's persisted authorized issue.
  --repo PATH                Repository to track.
  --state-file PATH          Authorization state file; it remains bound to --repo.
  --limit NUMBER             Read limit when no issue is authorized. Range: 1-50. Default: 30.
  --dry-run                  Inspect GitHub work without changing state.
  --help                     Show this help.
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
    --authorize)
      require_value "$1" "${2:-}"
      authorize_issue="$2"
      shift 2
      ;;
    --clear-authorization)
      clear_authorization=1
      shift
      ;;
    --repo)
      require_value "$1" "${2:-}"
      repo_dir="$2"
      shift 2
      ;;
    --state-file)
      require_value "$1" "${2:-}"
      state_file="$2"
      shift 2
      ;;
    --limit)
      require_value "$1" "${2:-}"
      limit="$2"
      shift 2
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

[[ "$limit" =~ ^[1-9][0-9]*$ && "$limit" -le "$max_limit" ]] || fail "limit must be an integer from 1 to $max_limit"
[[ -z "$authorize_issue" || "$authorize_issue" =~ ^[1-9][0-9]*$ ]] || fail 'issue must be a positive integer'
[[ -z "$authorize_issue" || "$clear_authorization" -eq 0 ]] || fail 'authorize and clear cannot be used together'
[[ -d "$repo_dir/.git" || -f "$repo_dir/.git" ]] || fail "repository is not a Git checkout: $repo_dir"
repo_dir="$(git -C "$repo_dir" rev-parse --show-toplevel)"
repo_remote="$(git -C "$repo_dir" config --get remote.origin.url || true)"
[[ -n "$repo_remote" && "$repo_remote" != *$'\n'* && "$repo_remote" != *$'\r'* ]] || fail 'repository must have a safe origin remote'

if [[ -z "$state_file" ]]; then
  state_key="$(printf '%s\n%s' "$repo_dir" "$repo_remote" | shasum -a 256 | awk '{print $1}')"
  state_file="$state_root/${state_key}.state"
fi

[[ "$state_file" != "/" && "$state_file" != "." ]] || fail 'unsafe state file'
[[ ! -L "$state_file" ]] || fail "refusing symbolic-link state file: $state_file"
[[ ! -e "$state_file" || -f "$state_file" ]] || fail "state path is not a regular file: $state_file"
state_dir="$(dirname "$state_file")"

write_state() {
  local issue="$1" status="$2" temporary
  mkdir -p "$state_dir"
  temporary="$(mktemp "${state_file}.tmp.XXXXXX")"
  chmod 600 "$temporary"
  printf 'version=1\nrepo=%s\nremote=%s\nissue=%s\nstatus=%s\n' "$repo_dir" "$repo_remote" "$issue" "$status" > "$temporary"
  mv -f "$temporary" "$state_file"
}

read_state() {
  local key value version=""
  [[ ! -L "$state_file" && -f "$state_file" ]] || fail "refusing unsafe authorization state: $state_file"
  state_issue=""; state_status=""; state_repo=""; state_remote=""
  while IFS='=' read -r key value; do
    case "$key" in
      version) [[ -z "$version" ]] || fail 'authorization state has duplicate version'; version="$value" ;;
      repo) [[ -z "$state_repo" ]] || fail 'authorization state has duplicate repository'; state_repo="$value" ;;
      remote) [[ -z "$state_remote" ]] || fail 'authorization state has duplicate remote'; state_remote="$value" ;;
      issue) [[ -z "$state_issue" ]] || fail 'authorization state has duplicate issue'; state_issue="$value" ;;
      status) [[ -z "$state_status" ]] || fail 'authorization state has duplicate status'; state_status="$value" ;;
      *) fail 'authorization state has an unsupported field' ;;
    esac
  done < "$state_file"
  [[ "$version" == '1' && "$state_issue" =~ ^[1-9][0-9]*$ ]] || fail 'authorization state is invalid'
  [[ "$state_status" == 'authorized' || "$state_status" == 'completed' ]] || fail 'authorization state has an invalid status'
  [[ "$state_repo" == "$repo_dir" && "$state_remote" == "$repo_remote" ]] || fail 'authorization belongs to a different repository'
}

list_open_work() {
  command -v gh >/dev/null || fail 'gh CLI is required'
  (
    cd "$repo_dir"
    gh issue list --state open --limit "$limit" --json number,title,url >/dev/null
    gh pr list --state open --limit "$limit" --json number,title,url >/dev/null
  )
}

if [[ -n "$authorize_issue" ]]; then
  if [[ -e "$state_file" ]]; then
    read_state
    [[ "$state_issue" == "$authorize_issue" && "$state_status" == 'authorized' ]] || fail "issue #$state_issue is already recorded; clear it before authorizing another issue"
  else
    write_state "$authorize_issue" 'authorized'
  fi
  printf 'Authorized issue #%s for %s\n' "$authorize_issue" "$repo_remote"
  exit 0
fi

if [[ "$clear_authorization" -eq 1 ]]; then
  if [[ -e "$state_file" ]]; then
    read_state
    rm -f -- "$state_file"
  fi
  printf 'Cleared authorization state for %s\n' "$repo_remote"
  exit 0
fi

if [[ ! -e "$state_file" ]]; then
  list_open_work
  printf 'No authorized issue. Monitoring completed without starting Claude.\n'
  exit 0
fi

read_state
if [[ "$state_status" == 'completed' ]]; then
  printf 'Authorized issue #%s has already completed.\n' "$state_issue"
  exit 0
fi

command -v gh >/dev/null || fail 'gh CLI is required'
issue_state="$(cd "$repo_dir" && gh issue view "$state_issue" --json state --jq '.state')"
if [[ "$issue_state" != 'OPEN' ]]; then
  write_state "$state_issue" 'completed'
  printf 'Authorized issue #%s is no longer open; marked completed.\n' "$state_issue"
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Authorized issue #%s is ready for interactive execution in %s\n' "$state_issue" "$repo_dir"
  exit 0
fi

printf 'Authorized issue #%s is tracked and requires interactive execution.\n' "$state_issue"
