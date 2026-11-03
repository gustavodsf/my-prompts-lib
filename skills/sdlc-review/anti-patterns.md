# Anti-pattern catalog

Structural problems a diff-by-diff review tends to miss because each hunk looks fine on its own. Used by review (Phase 1 step 11, feature reviewer 4), by the Goldfish `simplicity` lens on `design.md`, and by `sdlc-implement` before declaring done.

**The bar still applies.** An anti-pattern is reported only with a named failure scenario (a concrete future change or input that breaks, diverges, or cannot be tested), a `file:line`, and a verify label. "This class is big" is not a finding; "the next payment rule must be edited in `X.ts:40` and `Y.ts:88`, and the diff already changed only one" is. Only report what the diff **introduces or worsens**, never pre-existing debt it merely touches.

Cite findings as `AP-XXX`. Default severity in brackets; raise it when the scenario is already happening in the diff.

## Duplication

### AP-001 — Duplicated logic [Warning]
- Signal: the same rule, validation, mapping, query, or calculation appears in two or more places (copy-paste, or re-derived with small differences), including across front and back end.
- Scenario: a later change updates one copy; the other keeps the old behavior. Already diverging copies → Critical/High.
- Check: grep distinctive literals, field names, and conditions from new code across the repo; compare with `codemap.md` for an existing helper.
- Fix: extract to one owner and call it from both; or reuse the existing helper.

### AP-002 — Parallel constants and enums [Warning]
- Signal: status lists, limits, role names, or magic numbers redefined instead of imported.
- Scenario: a new value is added to one list only.
- Fix: single source of truth exported from the owning module.

## Size and responsibility

### AP-010 — God class / god module [Warning]
- Signal: one class, service, component, or file that the diff makes responsible for several unrelated concerns (e.g. validation + persistence + HTTP + notifications), or that grows past ~400 lines / ~15 public methods because of this change.
- Scenario: two unrelated features must now edit the same unit; a test of one concern needs the whole unit's dependencies.
- Check: list the reasons this unit would change; more than one domain reason is the smell.
- Fix: split by responsibility along existing project layers.

### AP-011 — Long method [Suggestion]
- Signal: a function the diff makes longer than ~50 lines or with nesting deeper than 3.
- Scenario: a branch cannot be tested in isolation, or an early-return guard gets lost in an edit.
- Fix: extract named steps; guard clauses instead of nesting.

### AP-012 — Long parameter list / boolean flag argument [Suggestion]
- Signal: more than 4 positional parameters, or a boolean that switches behavior (`save(x, true)`).
- Scenario: callers swap two same-typed arguments; the flag hides two functions.
- Fix: parameter object; two named functions.

## Coupling and design

### AP-020 — Feature envy / leaking internals [Warning]
- Signal: code reaches through another module's objects (`a.b.c.d`) or reimplements logic that belongs to the data's owner; ORM/Prisma types escaping the repository.
- Scenario: a schema change in the owner breaks distant callers.
- Fix: move the behavior to the owner; return a DTO.

### AP-021 — Shotgun surgery [Warning]
- Signal: one conceptual change in the diff touches many files with near-identical edits.
- Scenario: the next change of the same kind misses one file.
- Fix: centralize the varying part.

### AP-022 — Primitive obsession [Suggestion]
- Signal: money as float, IDs/phones/emails as raw strings validated in several places.
- Scenario: a raw value bypasses validation at one call site; float rounding on money.
- Fix: value type or branded type validated once at the boundary.

### AP-023 — Speculative generality [Suggestion]
- Signal: abstractions, options, or extension points no acceptance criterion needs (single-implementation interfaces, unused params, config nobody sets).
- Scenario: extra paths without tests that the next change must keep working.
- Fix: delete; add it when the second case exists.

### AP-024 — Dead code [Suggestion]
- Signal: unreachable branches, unused exports, commented-out code, or behavior replaced but the old path left in.
- Scenario: someone fixes or calls the dead path believing it is live.
- Fix: delete it.

## Error handling and state

### AP-030 — Swallowed errors [High]
- Signal: empty `catch`, `catch` that only logs and continues, default values hiding failures.
- Scenario: a failed write is reported as success.
- Fix: rethrow, return a typed error, or handle explicitly.

### AP-031 — Hidden shared mutable state [High]
- Signal: module-level mutable variables, singletons holding request data, mutation of arguments.
- Scenario: concurrent requests (or Lambda warm reuse) leak data between tenants.
- Fix: pass state explicitly; keep module scope immutable.

## Tests

### AP-040 — Tests coupled to implementation [Suggestion]
- Signal: tests that assert private calls or mock the unit under test, or that are copy-pasted per case instead of parameterized.
- Scenario: a correct refactor breaks the tests; a behavior regression passes them.
- Fix: test at the boundary; table-driven cases.

## Adding an entry

When a structural miss reaches review or production, add `AP-XXX` here with Signal, Scenario, Check (when not obvious), and Fix, and mention it in `sdlc/error.md` if it is a process failure.
