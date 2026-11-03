---
name: sdlc-plan
description: Create or update a local design document (design.md, max 150 lines) and run a Goldfish check for a ClickUp/Jira task or an explicitly authorized GitHub issue. Use after project context is available and before implementation.
argument-hint: "[task identifier or issue number]"
---

# Design

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Use [../../sdlc/templates/design.md](../../sdlc/templates/design.md). Keep one `project-doc/<task-or-issue-id>/design.md` (max 150 lines) out of commits. It replaces the former business-logic, code-sequence, implementation, and plan documents: do not create those.

Read `project-doc/_project/INDEX.md` first; if it is missing or stale, run `sdlc-project-context`.

## Mode selection

- **Guided mode:** require the ClickUp/Jira task identifier supplied by the user. Keep the user at business and approval gates. Do not access AWS.
- **GitHub mode:** require an issue number and explicit `vamos trabalhar <issue-number>` authorization before writing a plan comment or changing any external state. Use the number in the branch, local documents, issue comments, and pull request.

## Ticket

Resolve the task from the argument or the branch name (`PROJ-1234-...` → `PROJ-1234`); if neither yields a valid `<PROJECT>-<NUMBER>` or issue number, ask the user. Fetch the summary, status, and acceptance criteria through the ClickUp or Jira integration once, and reuse them for planning, QA, and review. Warn when the ticket is already done or closed. Without an integration, ask the user to paste the criteria; never guess them from the branch or pull request.

## Design contents

A `Type: bug | feature` header from `sdlc-intake`, then exactly five sections: problem and acceptance criteria; solution options and trade-offs (at least two options, the choice and why); flow with **one** Mermaid diagram; files and TDD tasks; out of scope. A bug keeps it short: reproduction as the current behavior, one regression AC, the fix option, no diagram unless the path is unclear. Every file and symbol named must exist in `project-doc/_project/codemap.md` (grep it) or be marked `(new)`. Cite business rules by id (`R-03`), do not restate them.

Every acceptance criterion `AC-n` names its acceptance test (file and test name). Task 0 writes all AC tests and shows them failing; the design is not ready if any AC lacks a test. Name the agents for each phase from [../../sdlc/agents.yml](../../sdlc/agents.yml).

Choose evidence that matches the changed surface: HTTP client evidence for APIs and visible front-end evidence for UI/E2E. AWS follows the [safety rules](../../sdlc/SDLC.md#safety-rules).

## Goldfish check

Before presenting or posting the design, run [../../sdlc/goldfish.md](../../sdlc/goldfish.md): a context-free subagent reads `design.md`, `INDEX.md`, and `codemap.md`, explains the plan back, and lists symbols that do not exist. Fix every Fail in its Pass/Partial/Fail grades; do not save the Goldfish output.

## AIDOS card

When a hand-off card is asked for, run [aidos-card.sh](aidos-card.sh) `<design.md>`: it prints the four AIDOS blocks (Problem → Solution → Tech Design → Testing, https://github.com/shobman/aidos) built only from the design's sections, so the card never drifts from it.

For an authorized GitHub issue, prepare a concise sanitized plan comment that mirrors the design's criteria, tasks, and validation. The skill does not create branches, commits, pull requests, or AWS requests.
