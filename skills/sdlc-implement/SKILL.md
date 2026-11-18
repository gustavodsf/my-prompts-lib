---
name: sdlc-implement
description: Implement an approved design.md, then write an acceptance test for every AC against its how-to-verify, and stop only when all of them pass. Use after the design is approved and before review.
argument-hint: "[task identifier or issue number]"
---

# Implement (tests after the change)

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Run as the `implement` agent from [../../sdlc/agents.yml](../../sdlc/agents.yml). Inputs: the approved `project-doc/<task-or-issue-id>/design.md` and `project-doc/_project/codemap.md`.

Read `Mode:` in `design.md` ([implementation modes](../../sdlc/SDLC.md#implementation-modes)).

1. **Guided mode: scaffold, then stop.** Write no production logic and no tests yet. At each place the design's tasks change, insert a comment block in that file's comment syntax, each line starting `SDLC-PSEUDO`: the task and AC, the real calls in order with signatures from `codemap.md` (`path#symbol`, or `(new)` with the signature to create), inputs, outputs and errors. Then list every block as `file:line — what to write` and stop; the owner implements. After the owner says `pronto`, write the AC tests (step 3), run the checks, and `agent-run.sh pseudo-check` (no `SDLC-PSEUDO` left) before review.
2. **Auto mode: implement in checkpoints.** Work the design's tasks in order. After each finished task, check `agent-run.sh diff-lines <cwd> <last checkpoint ref>`; at or over the threshold (default 250), stop at that task boundary (never mid-task unless one task alone exceeds it), commit the checkpoint and report the diff summary, tasks done and tasks next; continue only after `segue` or applied feedback.
3. **Tests after the change.** For every `AC-n` in the design, write the named acceptance test at the boundary it describes (HTTP, UI, or public API), against that AC's "how to verify" (command, page, or file plus expected result). Tests stay mandatory. Do not edit an AC test to make it pass; if an AC test is wrong, stop and update `design.md` with approval.
4. **Refactor before done.** With tests green, check your diff against [../sdlc-review/anti-patterns.md](../sdlc-review/anti-patterns.md): reuse existing helpers from `codemap.md` instead of duplicating logic, and split any unit you made responsible for more than one concern. Keep refactors inside the design's files.
5. **Build log.** After each implementation or fix round (including each auto checkpoint and after a guided `pronto`), append a **Build log** block to `project-doc/<task-or-issue-id>/evidence.md` (see [../../sdlc/templates/evidence.md](../../sdlc/templates/evidence.md)): commands run and what was observed, and an AC checklist. Do not overwrite earlier rounds.
6. **Done** only when every AC test passes together with lint, typecheck, and the focused tests. A skipped, deleted, or pending AC test means not done.
7. Append a row to `project-doc/<task-or-issue-id>/metrics.md` for each attempt (phase `implement`, agent, tokens if known, attempt, AC tests passing x/y), plus one row per checkpoint (phase `checkpoint-<n>`, lines changed, tasks done) or per guided hand-off (phase `scaffold`, number of blocks).

Hand off to `sdlc-review` with the `review` agent, which must not be you. Follow the [safety rules](../../sdlc/SDLC.md#safety-rules).
