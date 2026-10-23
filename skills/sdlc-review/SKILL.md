---
name: sdlc-review
description: Run a final cross-agent review of an approved feature diff and produce a local review record. Use after validation and before declaring a task or authorized GitHub issue complete.
---

# Cross-agent review

Review only the current feature diff and its direct interactions. Do not modify code, task artifacts, GitHub, or AWS during review.

Determine the implementing agent. If Claude implemented the work, run the four independent reviews in Codex. If Codex implemented the work, run them in Claude. If the opposite agent is unavailable, record the limitation and do not report review completion.

Before launching reviewers, prepare a shared review brief with the feature objective, acceptance criteria, base and feature commits, complete diff, relevant full-file context, owned files or flows, and claims made in the task, issue, or pull request that need independent verification. Split files or flows by natural boundaries when useful, while preserving the four review areas and cross-checking direct interactions.

Use four reviewers with these areas:

1. Correctness, regressions, error handling, and test coverage.
2. Performance, resource use, and unnecessary work. Check N+1 queries, unbounded reads, pagination, inefficient joins, missing indexes for new hot queries, repeated network or disk work, avoidable serialization, cache behavior, and resource cleanup. Require query/benchmark evidence when the change makes a performance claim.
3. Security. Check input validation and injection boundaries, authentication, authorization, tenant scoping, insecure defaults, secret/cookie/token/PII exposure in code or logs, sensitive error responses, dependency/configuration risk, and least-privilege AWS access. Treat AWS write operations in automated flows as a policy violation.
4. Duplication, reuse, maintainability, and project patterns. Check duplicated business rules, validation, mappings, API contracts, queries, UI components, and helpers; identify an existing local pattern that the change should reuse; flag a new abstraction or convention that conflicts with existing project practice.

Across the four areas, also assess these cross-cutting risks when relevant to the changed behavior:

- Reliability: concurrent execution, idempotency, retries, timeouts, partial failures, rollback or compensation, and safe degradation.
- Data and compatibility: migrations, data loss, backward-compatible API and event contracts, defaults, and upgrade or rollback behavior.
- Observability: useful and sanitized logs, metrics, tracing or correlation, actionable errors, and absence of sensitive data in diagnostic output.
- Accessibility and UI: keyboard navigation, focus behavior, semantic controls, contrast, responsive desktop and mobile layouts, and adherence to the project's design system.
- Integrations and cost: rate limits, duplicate external calls, payload size, cache and retry behavior, cost-sensitive work, and graceful dependency failures.

Review the full context necessary to understand a changed line; do not infer behavior from diff hunks alone. Scale depth to the changed surface, but keep the four required review areas independent. Briefly record important checks that found no issue when they validate a high-risk claim.

Each finding needs severity, changed-file location, concrete mechanism, a reproducible failure scenario expressed as input or state followed by the incorrect outcome, supporting evidence, suggested correction, confidence, and relevant rule/error ID. Recheck each finding against existing code and tests before reporting it. Consolidate duplicates, discard vague or speculative observations, and retain at most ten material findings.

Store detail in local `review.md`. For an authorized GitHub issue, post only a concise sanitized summary and decisions. Post an inline pull-request comment only when the review request explicitly authorizes it and the finding has a valid anchor on a changed line; otherwise retain it in the local record or issue summary. Do not include secrets, credentials, personal data, internal endpoints, or raw AWS data. Do not use GitLab-specific tooling or force-remove worktrees or branches.
