---
name: sdlc-review
description: Run a final cross-agent review of an approved feature diff and produce a local review record. Use after validation and before declaring a task or authorized GitHub issue complete.
---

# Cross-agent review

Review only the current feature diff and its direct interactions. Do not modify code, task artifacts, GitHub, or AWS during review.

Determine the implementing agent. If Claude implemented the work, run the four independent reviews in Codex. If Codex implemented the work, run them in Claude. If the opposite agent is unavailable, record the limitation and do not report review completion.

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

Each finding needs severity, changed-file location, concrete failure behavior, supporting evidence, suggested correction, confidence, and relevant rule/error ID. Consolidate duplicates and retain at most ten material findings.

Store detail in local `review.md`. For an authorized GitHub issue, post only a concise sanitized summary and decisions. Do not include secrets, credentials, personal data, internal endpoints, or raw AWS data.
