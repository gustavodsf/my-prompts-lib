# SDLC feature review

Use this procedure for the final review of an approved feature and for every follow-up review after corrections. Each reviewer applies the standard in [SKILL.md](SKILL.md) and its [security-checklist.md](security-checklist.md); this file defines who reviews, what they receive, and how results are recorded. Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and use [../../sdlc/error.md](../../sdlc/error.md) as a checklist. Do not modify code, task artifacts, GitHub, or AWS during review.

## Reviewers

Work implemented with Claude is reviewed in Codex; work implemented with Codex is reviewed in Claude. If the opposite agent is unavailable, record the limitation and do not report review completion.

Prepare one shared brief: feature objective, acceptance criteria, recorded base and feature commits, complete diff, relevant full-file context, owned files or flows, and claims made in the task, issue, or pull request that need independent verification. Run four independent reviewers scoped to the feature diff:

1. Correctness, regressions, error handling, and test coverage.
2. Performance: N+1 queries, unbounded reads, pagination, inefficient joins, missing indexes for new hot queries, repeated network or disk work, avoidable serialization, cache behavior, and resource cleanup. Require query or benchmark evidence for performance claims.
3. Security: apply `security-checklist.md`; check tenant scoping, secret/cookie/token/PII exposure in code or logs, sensitive error responses, and least-privilege AWS access. AWS writes in automated flows are a policy violation.
4. Duplication and project patterns: duplicated rules, validation, mappings, contracts, queries, UI components, or helpers; an existing pattern the change should reuse; a new convention that conflicts with project practice.

When relevant, each area also checks reliability (idempotency, retries, timeouts, partial failure, rollback), data and compatibility (migrations, contracts, defaults, upgrade/rollback), observability (sanitized logs, actionable errors), accessibility and UI (keyboard, focus, contrast, responsive layout, design system), and integrations and cost (rate limits, duplicate calls, payload size).

Reviewers may read surrounding code only to understand direct interactions, confirm a regression caused by the feature, or identify code it should reuse. Do not report unrelated pre-existing problems.

## Findings

Every finding meets the bar in `SKILL.md`: named failure scenario, `file:line`, and a CONFIRMED or PLAUSIBLE verify label. Add severity, evidence, suggested correction, confidence, and the relevant rule or `sdlc/error.md` ID. Recheck each finding against existing code and tests, consolidate duplicates, and keep at most ten material findings.

## Follow-up review — delta mode

After approved corrections, do not repeat a full review. Give the reviewers the previous `review.md` findings and only the correction diff.

1. Classify each prior finding as **Fixed**, **Partially addressed**, **Accepted as-is** (with the user's recorded decision), or **Superseded**.
2. Report a new finding only when the correction diff introduced it and it is P0/P1, or it directly breaks an approved correction. Record lower-severity observations as notes, not new findings.
3. Rerun only the affected review areas and the required checks.

This keeps each correction cycle bounded to verifying what changed.

## Record

Store detail in the local `project-doc/<task-or-issue-id>/review.md`: base commit, reviewed commit, diff scope, checks run, findings with status and disposition, accepted risks, and QA impact. Never commit it.

For an authorized GitHub issue, post only a concise sanitized summary and decisions. Post an inline pull-request comment only when the request explicitly authorizes it and the finding anchors to a changed line. Never include secrets, credentials, personal data, internal endpoints, or raw AWS data.
