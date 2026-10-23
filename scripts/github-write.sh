#!/usr/bin/env bash

set -euo pipefail

state_file="${APOLO_AUTHORIZATION_STATE:?authorization state is required}"
expected_repo="${APOLO_AUTHORIZED_REPO:?authorized repository is required}"
expected_remote="${APOLO_AUTHORIZED_REMOTE:?authorized remote is required}"
expected_issue="${APOLO_AUTHORIZED_ISSUE:?authorized issue is required}"

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

[[ "$state_file" != / && ! -L "$state_file" && -f "$state_file" ]] || fail 'unsafe authorization state'
[[ "$expected_issue" =~ ^[1-9][0-9]*$ ]] || fail 'invalid authorized issue'

state_version=""
state_repo=""
state_remote=""
state_issue=""
state_status=""
while IFS='=' read -r key value; do
  case "$key" in
    version) [[ -z "$state_version" ]] || fail 'authorization state has duplicate version'; state_version="$value" ;;
    repo) [[ -z "$state_repo" ]] || fail 'authorization state has duplicate repository'; state_repo="$value" ;;
    remote) [[ -z "$state_remote" ]] || fail 'authorization state has duplicate remote'; state_remote="$value" ;;
    issue) [[ -z "$state_issue" ]] || fail 'authorization state has duplicate issue'; state_issue="$value" ;;
    status) [[ -z "$state_status" ]] || fail 'authorization state has duplicate status'; state_status="$value" ;;
    *) fail 'authorization state has an unsupported field' ;;
  esac
done < "$state_file"

[[ "$state_version" == '1' && "$state_status" == 'authorized' ]] || fail 'authorization is not active'
[[ "$state_repo" == "$expected_repo" && "$state_remote" == "$expected_remote" && "$state_issue" == "$expected_issue" ]] || fail 'authorization context does not match the monitor'
repo_dir="$(git rev-parse --show-toplevel)"
repo_remote="$(git config --get remote.origin.url || true)"
[[ "$repo_dir" == "$expected_repo" && "$repo_remote" == "$expected_remote" ]] || fail 'current repository is not authorized'
command -v gh >/dev/null || fail 'gh CLI is required'

operation="${1:-}"
shift || true
case "$operation" in
  comment)
    [[ $# -eq 1 && -n "$1" && ${#1} -le 4000 ]] || fail 'comment requires one message up to 4000 characters'
    gh issue comment "$expected_issue" --body "$1"
    ;;
  push)
    [[ $# -eq 0 ]] || fail 'push does not accept arguments'
    branch="$(git branch --show-current)"
    [[ -n "$branch" && "$branch" != 'main' && "$branch" != 'master' && "$branch" == *"$expected_issue"* ]] || fail 'current branch is not authorized for this issue'
    git push --set-upstream origin "$branch"
    ;;
  create-pr)
    [[ $# -eq 2 && -n "$1" && ${#1} -le 120 && ${#2} -le 4000 ]] || fail 'create-pr requires a title and body within the allowed limits'
    branch="$(git branch --show-current)"
    [[ -n "$branch" && "$branch" != 'main' && "$branch" != 'master' && "$branch" == *"$expected_issue"* ]] || fail 'current branch is not authorized for this issue'
    body="$2"$'\n\n'"Closes #$expected_issue"
    gh pr create --head "$branch" --title "$1" --body "$body"
    ;;
  *)
    fail 'supported operations: comment, push, create-pr'
    ;;
esac
