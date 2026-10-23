#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(pwd)"
state_file="${XDG_STATE_HOME:-${HOME}/.local/state}/apolo-sdlc/authorized-issue"
claude_bin="claude"
allowed_tools="Read,Glob,Grep,Edit,Write,Bash(git status *),Bash(git diff *),Bash(git branch *),Bash(git switch *),Bash(git add *),Bash(git commit *),Bash(git push *),Bash(git fetch *),Bash(git merge --ff-only *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(git remote *),Bash(git ls-files *),Bash(gh issue list *),Bash(gh issue view *),Bash(gh issue comment *),Bash(gh pr list *),Bash(gh pr view *),Bash(gh pr checks *),Bash(gh pr create *),Bash(curl *),Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(bun *),Bash(mvn *),Bash(gradle *),Bash(dotnet *),Bash(go *),Bash(pytest *)"
limit=30
dry_run=0
authorize_issue=""
clear_authorization=0

usage() {
  cat <<'EOF'
Usage: scripts/monitor.sh [options]

Options:
  --authorize ISSUE          Persist one explicitly authorized GitHub issue.
  --clear-authorization      Remove the persisted authorized issue.
  --repo PATH                Repository where Claude will run.
  --state-file PATH          Authorization state file.
  --claude-bin PATH          Claude CLI executable.
  --limit NUMBER             Issue and pull-request read limit. Default: 30.
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

[[ "$state_file" != "/" && "$state_file" != "." ]] || fail 'unsafe state file'
[[ "$limit" =~ ^[1-9][0-9]*$ ]] || fail 'limit must be a positive integer'
[[ -z "$authorize_issue" || "$authorize_issue" =~ ^[1-9][0-9]*$ ]] || fail 'issue must be a positive integer'
[[ -z "$authorize_issue" || "$clear_authorization" -eq 0 ]] || fail 'authorize and clear cannot be used together'
[[ ! -L "$state_file" ]] || fail "refusing symbolic-link state file: $state_file"
[[ ! -e "$state_file" || -f "$state_file" ]] || fail "state path is not a regular file: $state_file"

state_dir="$(dirname "$state_file")"

if [[ -n "$authorize_issue" ]]; then
  if [[ -e "$state_file" ]]; then
    current_issue="$(<"$state_file")"
    [[ "$current_issue" == "$authorize_issue" ]] || fail "issue $current_issue is already authorized; clear it before authorizing another issue"
  else
    mkdir -p "$state_dir"
    printf '%s\n' "$authorize_issue" > "$state_file"
  fi
  printf 'Authorized issue #%s\n' "$authorize_issue"
  exit 0
fi

if [[ "$clear_authorization" -eq 1 ]]; then
  [[ ! -L "$state_file" ]] || fail "refusing to remove symbolic-link state file: $state_file"
  rm -f "$state_file"
  printf 'Cleared authorization state\n'
  exit 0
fi

[[ -d "$repo_dir/.git" || -f "$repo_dir/.git" ]] || fail "repository is not a Git checkout: $repo_dir"
repo_dir="$(cd "$repo_dir" && pwd)"
command -v gh >/dev/null || fail 'gh CLI is required'

(
  cd "$repo_dir"
  gh issue list --state open --limit "$limit" --json number,title,url >/dev/null
  gh pr list --state open --limit "$limit" --json number,title,url >/dev/null
)

if [[ ! -e "$state_file" ]]; then
  printf 'No authorized issue. Monitoring completed without starting Claude.\n'
  exit 0
fi

[[ ! -L "$state_file" ]] || fail "refusing symbolic-link state file: $state_file"
issue="$(<"$state_file")"
[[ "$issue" =~ ^[1-9][0-9]*$ ]] || fail 'authorization state must contain one positive issue number'
(
  cd "$repo_dir"
  gh issue view "$issue" --json number,title,url >/dev/null
)

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Would invoke Claude for authorized issue #%s in %s\n' "$issue" "$repo_dir"
  exit 0
fi

command -v "$claude_bin" >/dev/null || fail "Claude CLI is required: $claude_bin"
lock_dir="${state_file}.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Authorized issue #%s is already running.\n' "$issue"
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT
prompt="Run the authorized GitHub issue lifecycle for issue #${issue} in this repository. Follow the installed sdlc-github-issue skill. Work only on this issue; do not advance another issue. GitHub writes are allowed only for this authorized issue and must be concise and sanitized. Do not access AWS unless necessary, and never create, update, delete, or mutate AWS resources."

(
  cd "$repo_dir"
  "$claude_bin" -p --permission-mode dontAsk --allowedTools "$allowed_tools" "$prompt"
)
