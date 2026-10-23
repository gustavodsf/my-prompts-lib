---
name: sdlc-qa
description: Plan and execute proportionate QA for an approved ClickUp/Jira task or authorized GitHub issue. Use after implementation and before final review or pull request completion.
---

# QA

Create local QA cases from the approved plan and store them under `project-doc/<task-or-issue-id>/`. Use synthetic data and state which environment is used.

## Validation surface

- **API:** run `curl` or an equivalent HTTP client in a user-visible terminal. Record request intent, status, sanitized response, and relevant authorization or tenant cases.
- **UI/E2E:** use a visible Chrome or Brave session. Exercise approved cases at desktop and mobile widths when responsive UI changed. Capture relevant screenshots and console/network outcomes.
- **Other work:** use an approved proportionate check, such as a job invocation, contract test, migration verification, or command-line result. Do not fabricate browser evidence.

For UI/E2E, run three iterations: the first full execution, a blind second execution by the opposite agent when available, and a third confirmation run that reproduces reported failures. Do not substitute headless execution for the visible browser path by default. If the opposite agent or browser is unavailable, record the limitation instead of claiming an equivalent run.

Classify a failure as confirmed only when it recurs in at least two iterations. Record one-off failures as flaky and disagreeing runs as divergent. Summarize the evidence for the task/issue without exposing sensitive data.

AWS is prohibited in guided mode. In authorized GitHub mode, only necessary read-only AWS inspection is allowed. Keep QA Markdown out of commits.
