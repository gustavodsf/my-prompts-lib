---
description: Build or refresh local architecture, back-end, and front-end context before planning work in a project.
argument-hint: [task or issue identifier]
---

# Project context

Use the `sdlc-project-context` skill.

Inspect the target repository before proposing work. Create or refresh local `architecture.md`, `back-end.md`, and `front-end.md` when context is absent or stale. Keep these documents outside the repository and use the task/issue identifier in their directory.

Capture the existing design system in `front-end.md`. Reuse its components, tokens, typography, colors, spacing, responsiveness, and accessibility patterns. Record missing evidence as a risk.

Do not access AWS. Do not alter production, test, or repository documentation files.
