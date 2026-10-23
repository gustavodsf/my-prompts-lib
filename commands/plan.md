---
description: Create or update the local execution plan for an approved ClickUp/Jira task or authorized GitHub issue.
argument-hint: [task identifier or issue number]
---

# Execution plan

Use the `sdlc-plan` skill.

Determine the mode before planning. Guided mode requires the ClickUp/Jira task supplied by the user. GitHub mode requires an issue and explicit `vamos trabalhar <issue-number>` authorization before any external write.

Create or update only the local `plan.md`. Cover scope, rules, acceptance criteria, allowed files, validation type, design-system constraints, evidence, and ordered tasks. In authorized GitHub mode, prepare the matching issue-plan comment from the sanitized plan. Do not create a branch, commit, pull request, or AWS request in this command.
