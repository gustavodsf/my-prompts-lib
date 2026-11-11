---
name: sdlc-evidence
description: Capture and index sanitized verification evidence for an approved task or authorized GitHub issue. Use when API or UI/E2E validation has produced commands, responses, logs, or screenshots.
argument-hint: "[task identifier or issue number]"
---

# Evidence

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Use [../../sdlc/templates/evidence.md](../../sdlc/templates/evidence.md) to create or update local `project-doc/<task-or-issue-id>/evidence.md`. When updating, keep any **Build log** blocks already written by `sdlc-implement`. Use synthetic data whenever possible.

## Evidence selection

- **API work:** run the HTTP command in a user-visible terminal and record its command, status, and sanitized response. Prefer `curl` when it represents the real interface.
- **UI/E2E work:** run the visible user flow in a browser, then record relevant desktop/mobile captures and console/network result. Do not require duplicate HTTP evidence unless it is needed to diagnose a failure.

Sanitize every artifact before display, sharing, or a GitHub comment, per the [safety rules](../../sdlc/SDLC.md#safety-rules), which also govern AWS evidence. Preserve the original only in the controlled local artifact location when permitted by the project.

Keep task-generated evidence Markdown out of commits. In GitHub mode, publish only a concise sanitized summary to the authorized issue.
