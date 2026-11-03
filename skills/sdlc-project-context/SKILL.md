---
name: sdlc-project-context
description: Create or refresh the durable project context (INDEX, one-page architecture, business rules, decisions) and regenerate the code map before planning work. Use when beginning work in an unfamiliar repository or when its stored context is stale.
argument-hint: "[task or issue identifier]"
---

# Project context (the Elephant)

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Context is **per project, not per task**. Store it outside the repository in `project-doc/_project/`. Use [../../sdlc/templates/project-context.md](../../sdlc/templates/project-context.md) for structure and size limits.

## First run (no `_project/INDEX.md`)

Read repository instructions and inspect the project, then create:

- `INDEX.md` — max 30 lines, the single entry point.
- `architecture.md` — max 80 lines; one page covering what used to be architecture, back-end, and front-end context.
- `business-rules.md` — numbered rules, one line each.
- `decisions.md` — short ADRs, max 5 lines each.
- `codemap.md` — generated, see below.

## Later runs (INDEX exists)

Do not rewrite. Regenerate `codemap.md`, compare the commit recorded in `INDEX.md` with `HEAD` (`git diff --stat <commit>..HEAD`), and edit only the lines the change affects. Update the `Updated:` line. If a file would exceed its limit, cut; do not add a new file.

## Code map

Regenerate, never hand-write:

```bash
node <this-skill-dir>/codemap.mjs <repo-root> > project-doc/_project/codemap.md
# Windows PowerShell: node <this-skill-dir>\codemap.mjs <repo-root> --out project-doc\_project\codemap.md
```

[codemap.mjs](codemap.mjs) sits beside this file and needs the TypeScript 5.x compiler API from the project (`npm i -D typescript@5` if absent; TypeScript 7 has no JS API). For non-TypeScript projects use `npx repomix --compress --style markdown -o project-doc/_project/codemap.md`. Grep `codemap.md` on demand (`rg 'OrderService' codemap.md`) instead of reading it whole.

Hand-written files never list method or function names; point to directories and let `codemap.md` hold symbols.

## Rules

Ground every line in the repository. If no front end or design system exists, record that and its planning impact; do not invent one. Do not change repository files or create external records. Follow the [safety rules](../../sdlc/SDLC.md#safety-rules). Present the diff of the context for approval before detailed planning.
