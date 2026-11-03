# Durable project context template (the Elephant)

One set per project, in `project-doc/_project/`. Never per task. Generate once, then update only what changed. Write prose in the language chosen for planning artifacts.

Hand-written files describe intent, boundaries, and rules. They never list method or function names: symbols live only in the generated `codemap.md`.

## INDEX.md — max 30 lines

The only entry point. Read it first in every session.

```markdown
# <project> — index
Updated: <YYYY-MM-DD> at <commit>

- Architecture: architecture.md
- Business rules: business-rules.md
- Decisions: decisions.md
- Code map (generated, grep it): codemap.md
- Verify: <test/lint/build commands>
- Active task: project-doc/<task-id>/design.md | none

## By-the-way backlog
- BTW-01: <one line> (<file or area>)
```

## architecture.md — max 80 lines

One page. Merges the former `architecture.md`, `back-end.md`, and `front-end.md`.

- Purpose (2–3 lines)
- Modules and their responsibility (one line each, directories not methods)
- Entry points, integrations, data stores
- Data, auth, tenancy, and deployment boundaries
- Front end: apps, routes, design system (components, tokens, typography, colors, spacing, accessibility) or "no design system — risk"
- Risks and unknowns

## business-rules.md — one line per rule

```markdown
- R-01: <rule, in domain terms> — source: <ticket/issue/code path>
```

Numbers are stable: never renumber; mark a removed rule `R-07: (retired <date>)`.

## decisions.md — short ADRs, max 5 lines each

```markdown
## D-01 <title> (<YYYY-MM-DD>)
Context: <one line>. Decision: <one line>. Why: <one line>. Consequence: <one line>.
```

## codemap.md — generated, never hand-written

Created by `scripts/codemap.mjs` (or `repomix --compress`, see `sdlc/SDLC.md`). Modules, files, and exported signatures without bodies. Regenerate; never edit.
