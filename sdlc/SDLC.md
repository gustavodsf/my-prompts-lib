# Shared SDLC

Use this workflow for implementation work. Follow repository instructions when they are stricter.

## Source of work

Choose one mode before planning:

- **Guided mode:** the user supplies a ClickUp or Jira task. Keep task documents under `project-doc/<task-id>/` and wait at the agreed decision gates. Do not access AWS in this mode.
- **GitHub mode:** work belongs to a GitHub issue. Monitor issues and pull requests without writing. Start only after the user says `vamos trabalhar <issue-number>`.

After GitHub authorization, use the issue number in the branch, local documents, issue comments, and pull request. Run the authorized lifecycle through planning, implementation, validation, review, and pull request creation. Update the issue with the execution plan, material progress, blockers, sanitized validation summaries, and the pull request link. Do not act on another issue after a restart unless its authorization is still recorded.

## Project context

On the first interaction with a project, inspect its instructions and create local `architecture.md`, `back-end.md`, and `front-end.md` before detailed planning. The front-end context must identify the existing design system. Reuse its components, tokens, typography, spacing, colors, and accessibility patterns. Record a missing design system as a risk; do not invent one silently.

## Planning and evidence

Use one `plan.md` per task or issue. Keep task-generated plan, QA, evidence, review, and context Markdown out of commits. Versioned configuration under `sdlc/` and `README.md` may be committed.

- API work uses `curl` or an equivalent HTTP client with synthetic data. Record the command, status, and sanitized response.
- UI/E2E work uses the visible front end as the primary evidence. Capture relevant screenshots and console/network results.
- Keep an `evidence.md` index. Remove secrets, cookies, authorization headers, personal data, and internal-only values before displaying or posting evidence.

In GitHub mode, an authorized automated issue flow may perform AWS read-only inspection when needed. It must never create, update, or delete AWS resources. Never publish AWS credentials, account identifiers, internal endpoints, or unredacted results.

## Quality and review

Write a failing test when meaningful. When it is not meaningful, obtain approval for a proportionate alternative verification.

Code comments must be minimal. Add one only for a non-obvious invariant, constraint, compatibility need, security tradeoff, or performance reason.

Work implemented with Claude is reviewed in Codex; work implemented with Codex is reviewed in Claude. If the opposite agent is unavailable, do not report the review as complete.

Use `error.md` during planning, QA, and review. A repeated failure becomes an error-catalog rule with a prevention check.

## Installation behavior

The managed clone is the source of truth for Claude and Codex rules, commands, skills, templates, and the error catalog. Before creating a managed link, rename an existing managed file to `<name>-old-<timestamp>` in the same directory. Refuse existing links, paths outside expected configuration directories, and unmanaged files unless explicit replacement is authorized.
