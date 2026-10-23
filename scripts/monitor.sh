#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(pwd)"
state_file=""
state_root="${XDG_STATE_HOME:-${HOME}/.local/state}/apolo-sdlc"
claude_bin="claude"
allowed_tools="Read,Glob,Grep,Edit,Write,Bash(git status *),Bash(git diff *),Bash(git branch *),Bash(git switch *),Bash(git add *),Bash(git commit *),Bash(git fetch *),Bash(git merge --ff-only *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(git remote *),Bash(git ls-files *),Bash(gh issue list *),Bash(gh issue view *),Bash(gh pr list *),Bash(gh pr view *),Bash(gh pr checks *),Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(bun *),Bash(mvn *),Bash(gradle *),Bash(dotnet *),Bash(go *),Bash(pytest *)"
limit=30
max_limit=50
lock_ttl=3600
dry_run=0
authorize_issue=""
clear_authorization=0
repo_remote=""
state_issue=""
state_status=""
state_repo=""
state_remote=""
lock_dir=""

usage() {
  cat <<'EOF'
Usage: scripts/monitor.sh [options]

Options:
  --authorize ISSUE          Persist one explicitly authorized GitHub issue for this repository.
  --clear-authorization      Remove this repository's persisted authorized issue.
  --repo PATH                Repository where Claude will run.
  --state-file PATH          Authorization state file; it remains bound to --repo.
  --claude-bin PATH          Claude CLI executable.
  --limit NUMBER             Read limit when no issue is authorized. Range: 1-50. Default: 30.
  --lock-ttl SECONDS         Recover a stale execution lock after this interval. Default: 3600.
  --dry-run                  List GitHub work but do not invoke Claude.
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
    --claude-bin)
      require_value "$1" "${2:-}"
      claude_bin="$2"
      shift 2
      ;;
    --limit)
      require_value "$1" "${2:-}"
      limit="$2"
      shift 2
      ;;
    --lock-ttl)
      require_value "$1" "${2:-}"
      lock_ttl="$2"
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
[[ "$lock_ttl" =~ ^[1-9][0-9]*$ ]] || fail 'lock TTL must be a positive integer'
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

release_lock() {
  [[ -n "$lock_dir" ]] || return 0
  rm -f -- "$lock_dir/owner"
  rmdir -- "$lock_dir" 2>/dev/null || true
}

lock_is_stale() {
  local owner_pid started_at now owner_data
  [[ -d "$lock_dir" && ! -L "$lock_dir" ]] || fail "unsafe execution lock: $lock_dir"
  [[ -f "$lock_dir/owner" && ! -L "$lock_dir/owner" ]] || return 0
  owner_data="$(<"$lock_dir/owner")"
  read -r owner_pid started_at <<< "$owner_data"
  [[ "$owner_pid" =~ ^[1-9][0-9]*$ && "$started_at" =~ ^[1-9][0-9]*$ ]] || return 0
  now="$(date +%s)"
  (( now - started_at > lock_ttl )) && return 0
  kill -0 "$owner_pid" 2>/dev/null || return 0
  return 1
}

acquire_lock() {
  lock_dir="${state_file}.lock"
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s %s\n' "$$" "$(date +%s)" > "$lock_dir/owner"
    trap release_lock EXIT INT TERM
    return 0
  fi
  if lock_is_stale; then
    rm -f -- "$lock_dir/owner"
    rmdir -- "$lock_dir" || fail "could not recover stale execution lock: $lock_dir"
    mkdir "$lock_dir" || fail "could not create execution lock: $lock_dir"
    printf '%s %s\n' "$$" "$(date +%s)" > "$lock_dir/owner"
    trap release_lock EXIT INT TERM
    return 0
  fi
  printf 'Authorized issue #%s is already running.\n' "$state_issue"
  return 1
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
  printf 'Would invoke Claude for authorized issue #%s in %s\n' "$state_issue" "$repo_dir"
  exit 0
fi

command -v "$claude_bin" >/dev/null || fail "Claude CLI is required: $claude_bin"
acquire_lock || exit 0
prompt="Run the authorized GitHub issue lifecycle for issue #${state_issue} in this repository. Follow the installed sdlc-github-issue skill. Work only on this issue; do not advance another issue. Direct external writes and AWS access are unavailable in automatic mode."
(
  cd "$repo_dir"
  "$claude_bin" -p --permission-mode dontAsk --allowedTools "$allowed_tools" "$prompt"
)
write_state "$state_issue" 'completed'
printf 'Authorized issue #%s completed.\n' "$state_issue"
