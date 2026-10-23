# Error catalog

Use these checks in planning, QA, and review. Add an entry when a failure repeats.

## Entry format

```markdown
### ERR-XXX — Short title
- Symptom:
- How to check:
- Prevention:
- Seen:
```

### ERR-001 — Work started without an authorized source
- Symptom: A branch, task, comment, or pull request is created without the specified issue/task.
- How to check: Confirm the task identifier and authorization before every external write.
- Prevention: GitHub mode requires `vamos trabalhar <issue-number>`.
- Seen: 0

### ERR-002 — Local task Markdown staged
- Symptom: Local plan, QA, evidence, review, or context Markdown is included in a commit.
- How to check: Inspect staged paths before committing.
- Prevention: Stage explicit paths. Versioned configuration under `sdlc/` and `README.md` are allowed; task-generated Markdown stays local.
- Seen: 0

### ERR-003 — Evidence exposes sensitive data
- Symptom: A log, response, screenshot, or comment exposes a token, cookie, authorization header, personal data, or internal value.
- How to check: Review evidence before publishing or sharing it.
- Prevention: Use synthetic data and sanitize evidence at capture time.
- Seen: 0

### ERR-004 — Wrong validation surface
- Symptom: API-only work requires browser proof, or UI/E2E work lacks visual evidence.
- How to check: Compare the changed surface with the planned evidence type.
- Prevention: Use HTTP evidence for APIs and front-end evidence for UI/E2E.
- Seen: 0

### ERR-005 — AWS write outside policy
- Symptom: A command creates, updates, or deletes AWS resources.
- How to check: Inspect AWS commands and SDK calls in the task evidence.
- Prevention: AWS is forbidden in guided mode and read-only in authorized GitHub automation.
- Seen: 0

### ERR-006 — Cross-agent review skipped
- Symptom: Claude work is approved without Codex review, or the inverse.
- How to check: Record the implementation and reviewer agent in `review.md`.
- Prevention: Block completion when the opposite agent is unavailable.
- Seen: 0

### ERR-007 — Unsafe managed-file replacement
- Symptom: A global configuration file is overwritten or an existing link is replaced without a recoverable copy.
- How to check: Exercise installation in a temporary configuration tree.
- Prevention: Rename managed targets with `-old-<timestamp>` and refuse existing links by default.
- Seen: 0

### ERR-008 — Design system bypassed
- Symptom: A UI change introduces inconsistent components, tokens, colors, spacing, or accessibility behavior.
- How to check: Compare the change with `front-end.md` and nearby UI patterns.
- Prevention: Capture the design system during project context before planning UI work.
- Seen: 0
