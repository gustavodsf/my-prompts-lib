---
name: sdlc-github-issue
description: Monitor GitHub issues and pull requests, then execute the complete lifecycle only for an explicitly authorized issue. Use for scheduled issue/PR automation or when the user says vamos trabalhar followed by an issue number.
---

# Authorized GitHub issue lifecycle

Monitor issues and pull requests without writing by default. Multiple candidate issues may exist. Start external work only after explicit `vamos trabalhar <issue-number>` authorization has been recorded in durable local state.

For an authorized issue:

1. Read the issue requirements and create/update local context and `plan.md`.
2. Create or update a sanitized issue-plan comment with objective, tasks, criteria, and validation.
3. Create the branch using the issue number and execute the approved work.
4. Add concise sanitized comments for material progress, blockers, validation, review, and pull request creation.
5. Run validation and the opposite-agent review before opening or updating the linked pull request.

Persist the authorization and issue number so a monitor restart cannot advance another issue. Keep generated task Markdown under `project-doc/<issue-number>/` and out of commits.

AWS is allowed only when necessary for the authorized issue and only through read-only inspection. Never create, update, delete, or mutate AWS resources. Sanitize AWS-derived evidence before writing a GitHub comment.
