---
name: sdlc-implement
description: Implement an approved design.md test-first, turning each acceptance criterion into a failing acceptance test before any production code, and stop only when all of them pass. Use after the design is approved and before review.
argument-hint: "[task identifier or issue number]"
---

# Implement (acceptance tests first)

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Run as the `implement` agent from [../../sdlc/agents.yml](../../sdlc/agents.yml). Inputs: the approved `project-doc/<task-or-issue-id>/design.md` and `project-doc/_project/codemap.md`.

1. **Red.** For every `AC-n` in the design, write the named acceptance test at the boundary it describes (HTTP, UI, or public API). Run them and confirm each fails for the expected reason, not for a setup error. Commit the tests alone when commits are approved.
2. **Green.** Work the design's tasks in order with normal TDD (unit test first when meaningful, minimal code). Do not edit an AC test to make it pass; if an AC test is wrong, stop and update `design.md` with approval.
3. **Done** only when every AC test passes together with lint, typecheck, and the focused tests. A skipped, deleted, or pending AC test means not done.
4. Append a row to `project-doc/<task-or-issue-id>/metrics.md` for each attempt (phase `implement`, agent, tokens if known, attempt, AC tests passing x/y).

Hand off to `sdlc-review` with the `review` agent, which must not be you. Follow the [safety rules](../../sdlc/SDLC.md#safety-rules).
