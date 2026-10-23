#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lane_mode="$repo_root/sdlc/lane-mode.md"
shared_rules="$repo_root/sdlc/SDLC.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  grep -qF -- "$2" "$1" || fail "$1 is missing: $2"
}

[[ -f "$lane_mode" ]] || fail "expected lane mode rules: $lane_mode"
require_text "$lane_mode" 'APOLO_SDLC_LANE'
require_text "$lane_mode" '<!-- apolo-sdlc-lane-prompt:'
require_text "$lane_mode" 'Guided mode'
require_text "$lane_mode" 'vamos trabalhar'

require_text "$shared_rules" '## Lane mode'
require_text "$shared_rules" 'lane-mode.md'
require_text "$shared_rules" '- **Guided mode:** the user supplies a ClickUp or Jira task.'
require_text "$shared_rules" 'Start only after the user says `vamos trabalhar <issue-number>`.'
require_text "$shared_rules" 'Write a failing test when meaningful.'

lane_skills=(sdlc-plan sdlc-qa sdlc-evidence sdlc-review sdlc-pr sdlc-github-issue)
for skill in "${lane_skills[@]}"; do
  skill_file="$repo_root/skills/$skill/SKILL.md"
  references="$(grep -F 'lane-mode.md' "$skill_file" || true)"
  [[ -n "$references" ]] || fail "$skill does not reference lane-mode.md"
  [[ "$(printf '%s\n' "$references" | wc -l)" -eq 1 ]] || fail "$skill references lane-mode.md more than once"
  [[ "$references" == 'Only in lane mode'* ]] || fail "$skill references lane-mode.md outside the conditional line"
done

for unaffected in "$repo_root/skills/sdlc-project-context" "$repo_root/skills/pr-watchdog" "$repo_root/sdlc/templates"; do
  if grep -rqF 'lane-mode.md' "$unaffected"; then
    fail "$unaffected must not reference lane-mode.md"
  fi
done

require_text "$repo_root/skills/sdlc-plan/SKILL.md" '- **Guided mode:** require the ClickUp/Jira task identifier supplied by the user.'
require_text "$repo_root/skills/sdlc-pr/SKILL.md" 'Push, create, or comment on a pull request only when the user explicitly asks in the current task.'
require_text "$repo_root/skills/sdlc-qa/SKILL.md" 'Do not substitute headless execution for the visible browser path by default.'
require_text "$repo_root/skills/sdlc-evidence/SKILL.md" 'run the HTTP command in a user-visible terminal'
require_text "$repo_root/skills/sdlc-review/SKILL.md" '**Standalone, write nothing.**'
require_text "$repo_root/skills/sdlc-github-issue/SKILL.md" 'Scheduled runs stay read-only even after authorization'
require_text "$repo_root/skills/sdlc-github-issue/SKILL.md" 'The read-only scheduled monitor (`monitor.sh`) never invokes Claude'

readme="$repo_root/README.md"
require_text "$readme" '## Autonomous lanes'
for text in '--lanes issue,ci' '--checkout' '--owner' 'sdlc/lane-mode.md' 'lanes/deny.json' 'APOLO_SDLC_LANE' \
  'logs/issue.log' 'last-error.log' 'without `--lanes`' 'aprovado'; do
  require_text "$readme" "$text"
done
if grep -qF 'scheduled runs remain read-only: they never start Claude' "$readme"; then
  fail 'README still says scheduled runs never start Claude without naming the read-only monitor'
fi

printf 'PASS: lane mode isolation\n'
