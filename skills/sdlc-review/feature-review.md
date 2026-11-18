# SDLC feature review

Use this procedure for the final review of an approved feature and for every follow-up review after corrections. Each reviewer applies the standard in [SKILL.md](SKILL.md) and its [security-checklist.md](security-checklist.md); this file defines who reviews, what they receive, and how results are recorded. Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and use [../../sdlc/error.md](../../sdlc/error.md) as a checklist. Do not modify code, task artifacts, GitHub, or AWS during review.

## Reviewers

The main reviewer is the `review` agent in `sdlc/agents.yml` (default Grok), and never the agent that implemented the change (see `SDLC.md#agents-per-phase`). If it is unavailable, record the limitation and do not report review completion. Disagreements after one round go to the `tiebreak` agent.

Prepare one shared brief: feature objective, acceptance criteria, recorded base and feature commits, complete diff, relevant full-file context, owned files or flows, and claims made in the task, issue, or pull request that need independent verification. The main reviewer covers, in one report, correctness and regressions, error handling and test coverage, performance (N+1, unbounded reads, pagination, indexes, repeated I/O, cleanup; require evidence for performance claims), security (`security-checklist.md`; tenant scoping, secret/cookie/token/PII exposure, least-privilege AWS; AWS writes in automated flows are a policy violation), and duplication and project patterns (reuse from `codemap.md`, conflicting conventions, and the structural anti-patterns in [anti-patterns.md](anti-patterns.md), cited by `AP-XXX`). When relevant, also check reliability, data and compatibility, observability, and integrations and cost.

If the change has a user-visible UI, also dispatch the `review_ui_ux` agent (default Codex; see [review-ui-ux.md](review-ui-ux.md)). That lens may share a CLI with the implementer: it still runs in a fresh read-only session with no implementer context.

Reviewers may read surrounding code only to understand direct interactions, confirm a regression caused by the feature, or identify code it should reuse. Do not report unrelated pre-existing problems.

## Rounds

Each review round lives in `project-doc/<task-or-issue-id>/round-<N>/` (or `<specDir>/round-<N>/` in a lane):

- `review.md` — the main `review` agent's report (always required)
- `review-ui.md` and `review-ux.md` — only when `review_ui_ux` was spawned for this change

Each file follows [output.md](output.md) and starts with `VERDICT: PASS | CHANGES | BLOCKED` on line 1. Treat a first line that still uses `Approved`, `Changes Requested`, or `Blocked` as `PASS`, `CHANGES`, or `BLOCKED`. The round closes only when every required file exists and has a readable first-line verdict. Never resume the implementer mid-round. If a reviewer finishes without writing its file, or writes a first line that is not a verdict, do not close the round.

After the round closes, write a short consolidation as `review.md` in the task folder (never committed; distinct from `round-<N>/review.md`): overall `VERDICT` on line 1 (`BLOCKED` if any required reviewer is `BLOCKED`; `CHANGES` if any is `CHANGES` and none is `BLOCKED`; `PASS` only if every required file is `PASS`), plus base and reviewed commits, diff scope, checks run, findings with status and disposition, accepted risks, and QA impact.

## Findings

Every finding meets the bar in `SKILL.md`: named failure scenario, `file:line`, and a CONFIRMED or PLAUSIBLE verify label. Add severity, evidence, suggested correction, confidence, and the relevant rule or `sdlc/error.md` ID. Recheck each finding against existing code and tests, consolidate duplicates, and keep at most ten material findings.

## Follow-up review — delta mode

After approved corrections, do not repeat a full review. Give the reviewers the previous `review.md` findings, the previous `round-<N>/` files, and only the correction diff. Write the follow-up into `round-<N+1>/`. Rerun the main review, and the UI/UX lenses if they were required for the original change (or if the correction introduced a visual change). Unaffected lenses still write their file (`PASS`, noting the area was unchanged) so the round can close. Close that round only when every required file exists, before any further implementation.

1. Classify each prior finding as **Fixed**, **Partially addressed**, **Accepted as-is** (with the user's recorded decision), or **Superseded**.
2. Report a new finding only when the correction diff introduced it and it is P0/P1, or it directly breaks an approved correction. Record lower-severity observations as notes, not new findings.
3. Rerun only the affected review areas and the required checks.

This keeps each correction cycle bounded to verifying what changed.

## Record

Keep `round-<N>/` and the consolidated `review.md` in `project-doc/<task-or-issue-id>/` (or `<specDir>/` in a lane). Never commit them. They are archived or deleted with the task folder.

## Human escalation gate

After a round closes (including a delta round), if the change touches money or billing, auth or permissions, deploy or CI, schema or migrations, production data or email, or adds a dependency, or if a design assumption is a product decision, write `project-doc/<task-or-issue-id>/decision.md` (never committed) before a pull request is opened:

```markdown
# <TASK ID> — Decision needed

## Why
What triggered this gate.

## For the human
The exact decision or check needed.

## Files to look at
- <path>
```

Agents never merge.

For an authorized GitHub issue, post only a concise sanitized summary and decisions. Post an inline pull-request comment only when the request explicitly authorizes it and the finding anchors to a changed line. Never include secrets, credentials, personal data, internal endpoints, or raw AWS data.
