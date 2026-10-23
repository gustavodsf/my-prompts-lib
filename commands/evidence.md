---
description: Capture and index sanitized API or UI/E2E evidence for the current approved task or authorized GitHub issue.
argument-hint: [task identifier or issue number]
---

# Evidence

Use the `sdlc-evidence` skill.

Write or update only local `evidence.md`. Run API evidence in a user-visible terminal and record the sanitized command output. Run UI/E2E evidence in a visible browser and record relevant captures. Use synthetic data and remove credentials, cookies, authorization headers, personal data, internal endpoints, and unredacted AWS results.

Do not access AWS in guided mode. In authorized GitHub mode, AWS evidence is read-only and only when required by the approved issue. Do not commit task-generated evidence Markdown.
