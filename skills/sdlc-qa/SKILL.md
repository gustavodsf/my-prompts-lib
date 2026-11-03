---
name: sdlc-qa
description: Plan and execute proportionate QA for an approved ClickUp/Jira task or authorized GitHub issue. Use after implementation and before final review or pull request completion.
argument-hint: "[task identifier or issue number]"
---

# QA

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Derive QA cases from the acceptance criteria in the approved `design.md`. Use synthetic data and state which environment is used.

## Validation surface

- **API:** run `curl` or an equivalent HTTP client in a user-visible terminal. Record request intent, status, sanitized response, and relevant authorization or tenant cases.
- **UI/E2E:** use a visible Chrome or Brave session. Exercise approved cases at desktop and mobile widths when responsive UI changed. Capture relevant screenshots and console/network outcomes.
- **Other work:** use an approved proportionate check, such as a job invocation, contract test, migration verification, or command-line result. Do not fabricate browser evidence.

For UI/E2E, run three iterations: the first full execution, a blind second execution by the opposite agent when available, and a third confirmation run that reproduces reported failures. Do not substitute headless execution for the visible browser path by default. If the opposite agent or browser is unavailable, record the limitation instead of claiming an equivalent run.

Classify a failure as confirmed only when it recurs in at least two iterations. Record one-off failures as flaky and disagreeing runs as divergent. Summarize the evidence for the task/issue without exposing sensitive data.

AWS, secrets, and data follow the [safety rules](../../sdlc/SDLC.md#safety-rules). Record QA cases and results in `evidence.md`; do not create a separate QA file. Keep it out of commits.
