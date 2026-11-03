---
name: sdlc-intake
description: Classify a new task or issue as bug or feature and ask the owner only the questions the text and code cannot answer (at most 5 per round), before any design. Use when a ClickUp/Jira task or authorized GitHub issue arrives and before sdlc-plan.
argument-hint: "[task identifier or issue number]"
---

# Intake

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

1. **Read first.** The task text, `project-doc/_project/INDEX.md`, `business-rules.md` and the code it touches (grep `codemap.md`). Never ask what these already answer.
2. **Classify.** `bug` = existing behavior differs from a rule, spec or previous behavior; everything else is `feature`. Write it as `Type:` at the top of `design.md`.
3. **Ask at most 5 questions per round**, numbered, each closed or with a proposed default ("Assume X unless you say otherwise"). Ask a new round only when an answer opens a new gap.
   - **Bug path (short):** steps to reproduce, expected vs actual, environment or data needed, since when / last good version. Skip any you could reproduce yourself.
   - **Feature path (full):** user and goal, acceptance criteria and edge cases, rules affected (`R-xx`), out of scope, constraints (permissions, performance, data migration).
4. **Implementation mode, always asked** (it does not count toward the 5): "`guided` — I place pseudocode and failing tests where you change the code, you implement — or `auto` — I implement and stop for your review about every 250 changed lines?" Record it as `Mode:` in `design.md`; no answer by the plan gate means `auto`.
5. **No other questions needed** → say so in one line and go to `sdlc-plan`. Record answers in `design.md` (criteria, rules, out of scope), never in a separate file.

In a lane, post the round as an `intake` comment (see `lanes/issue.md`); interactively, ask the user. Follow the [safety rules](../../sdlc/SDLC.md#safety-rules).
