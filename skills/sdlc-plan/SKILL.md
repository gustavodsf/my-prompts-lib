---
name: sdlc-plan
description: Create or update a local execution plan for a ClickUp/Jira task or an explicitly authorized GitHub issue. Use after project context is available and before implementation.
argument-hint: "[task identifier or issue number]"
---

# Execution plan

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Use [../../sdlc/templates/plan.md](../../sdlc/templates/plan.md) as the local structure. Keep the plan under `project-doc/<task-or-issue-id>/plan.md` and keep it out of commits.

## Mode selection

- **Guided mode:** require the ClickUp/Jira task identifier supplied by the user. Keep the user at business and approval gates. Do not access AWS.
- **GitHub mode:** require an issue number and explicit `vamos trabalhar <issue-number>` authorization before writing a plan comment or changing any external state. Use the number in the branch, local documents, issue comments, and pull request.

## Ticket

Resolve the task from the argument or the branch name (`PROJ-1234-...` → `PROJ-1234`); if neither yields a valid `<PROJECT>-<NUMBER>` or issue number, ask the user. Fetch the summary, status, and acceptance criteria through the ClickUp or Jira integration once, and reuse them for planning, QA, and review. Warn when the ticket is already done or closed. Without an integration, ask the user to paste the criteria; never guess them from the branch or pull request.

## Plan contents

Record the objective, acceptance criteria, business rules, scope, exclusions, affected context, design-system constraints, allowed files, ordered tasks, evidence type, verification, and risks.

Choose evidence that matches the changed surface: HTTP client evidence for APIs and visible front-end evidence for UI/E2E. AWS evidence is allowed only for an authorized GitHub issue and must be read-only.

For an authorized GitHub issue, prepare a concise sanitized plan comment that mirrors the plan's objective, tasks, criteria, and validation. The command/skill does not create branches, commits, pull requests, or AWS requests.
