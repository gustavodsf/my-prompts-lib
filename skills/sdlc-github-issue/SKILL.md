---
name: sdlc-github-issue
description: Monitor GitHub issues and pull requests without writes, then guide the interactive lifecycle only for an explicitly authorized issue. Use for scheduled tracking or when the user says vamos trabalhar followed by an issue number.
argument-hint: "[issue number]"
---

# Authorized GitHub issue lifecycle

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md).

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session ignore it.

Monitor issues and pull requests without writing by default. Multiple candidate issues may exist. Scheduled runs stay read-only even after authorization; start interactive work only after explicit `vamos trabalhar <issue-number>` authorization has been recorded in durable local state.

For an authorized issue:

1. Read the issue requirements and create/update local context and `plan.md`.
2. Create or update a sanitized issue-plan comment with objective, tasks, criteria, and validation.
3. Create the branch using the issue number and execute the approved work.
4. Add concise sanitized comments for material progress, blockers, validation, review, and pull request creation.
5. Run validation and the opposite-agent review before opening or updating the linked pull request.

Persist the authorization and issue number so a monitor restart cannot advance another issue. Keep generated task Markdown under `project-doc/<issue-number>/` and out of commits.

The read-only scheduled monitor (`monitor.sh`) never invokes Claude, `curl`, AWS, GitHub writes, `git push`, or a write wrapper. Run API evidence in a visible terminal and make GitHub writes only during the separately approved interactive workflow. Never create, update, delete, or mutate AWS resources.
