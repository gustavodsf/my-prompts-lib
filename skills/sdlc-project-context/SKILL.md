---
name: sdlc-project-context
description: Create or refresh local architecture, back-end, and front-end context before planning work in a new project. Use when beginning work in an unfamiliar repository or when its stored context is stale.
argument-hint: "[task or issue identifier]"
---

# Project context

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Read repository instructions and inspect the project before planning. Store local context outside the repository under `project-doc/<task-or-issue-id>/`.

Use [../../sdlc/templates/project-context.md](../../sdlc/templates/project-context.md) for their structure. Create or refresh these documents:

- `architecture.md`: system purpose, modules, entry points, integrations, data and authorization boundaries, deployment, repository instructions, verification commands, risks.
- `back-end.md`: APIs, jobs, events, stores, service boundaries, observability, test patterns, important dependencies, read/write and performance constraints.
- `front-end.md`: applications, routes, data flow, API clients, design system components/tokens/typography/colors/spacing/accessibility, responsive behavior, and visual-validation approach.

Use concise, factual descriptions grounded in the repository. If no front-end or design system exists, record that fact and its planning impact. Do not invent a design system.

Do not access AWS, change repository files, or create external records. Present the context for approval before detailed planning.
