# Shared SDLC

Use this workflow for implementation work. Follow repository instructions when they are stricter.

## Source of work

Choose one mode before planning:

- **Guided mode:** the user supplies a ClickUp or Jira task. Keep task documents under `project-doc/<task-id>/` and wait at the agreed decision gates. Do not access AWS in this mode.
- **GitHub mode:** work belongs to a GitHub issue. Monitor issues and pull requests without writing. Start only after the user says `vamos trabalhar <issue-number>`.

After GitHub authorization, use the issue number in the branch, local documents, issue comments, and pull request. Run the authorized lifecycle through planning, implementation, validation, review, and pull request creation. Update the issue with the execution plan, material progress, blockers, sanitized validation summaries, and the pull request link. Do not act on another issue after a restart unless its authorization is still recorded.

## Lane mode

An autonomous lane started by the monitor's lane runner runs in lane mode, defined in [lane-mode.md](lane-mode.md). It is active only when the lane runner set `APOLO_SDLC_LANE` and the prompt is a lane prompt. Guided mode and the interactive GitHub mode above never use it; in those sessions ignore `lane-mode.md`.

## Project context (Elephant) and task context

Keep two layers, and nothing else:

- **Durable, per project** — `project-doc/_project/`: `INDEX.md` (≤30 lines, the only entry point), `architecture.md` (≤80 lines, one page including front end and design system), `business-rules.md` (one line per numbered rule), `decisions.md` (ADRs ≤5 lines), and the generated `codemap.md`. Created once by `sdlc-project-context`, then updated only where the code changed. Reuse the existing design system; record a missing one as a risk, do not invent one.
- **Ephemeral, per task** — `project-doc/<task-or-issue-id>/`: `design.md` (≤150 lines, from `sdlc-plan`) and `evidence.md`. QA and review notes stay in the conversation or in `evidence.md`; do not add files.

`codemap.md` is generated from the code (`codemap.mjs` in `sdlc-project-context`, or `npx repomix --compress` for non-TypeScript projects) and never hand-written. Grep it on demand. Hand-written documents never list method or function names.

Before implementation, the design passes the [Goldfish check](goldfish.md): a parallel panel of context-free reviewers, one lens each (lenses from `agents.yml`; default: bug → comprehension, testability; feature → comprehension, testability, simplicity), grades it Pass/Partial/Fail; any Fail blocks.

Keep all task and context Markdown out of commits. Versioned configuration under `sdlc/` and `README.md` may be committed.

## End of task

When the pull request is open (or the task is abandoned):

1. **Promote** only what is durable: new or changed rules to `business-rules.md`, decisions to `decisions.md`, structural changes to `architecture.md`; regenerate `codemap.md`; update `INDEX.md`.
2. **Archive or delete** `project-doc/<task-or-issue-id>/` (move to `project-doc/_archive/` if you want history; the issue lane moves `<specDir>` to `<docs>/archive/` after the merge). Nothing in the task folder is read again.
3. **AIDOS card (optional).** `skills/sdlc-plan/aidos-card.sh <design.md>` prints the four blocks (Problem → Solution → Tech Design → Testing) for a hand-off or a PR description.

**By-the-way work** found during a task never gets its own document: add one line under `By-the-way backlog` in `INDEX.md` (`BTW-NN: <what> (<where>)`) or open an issue when authorized.

## Evidence

- API work uses `curl` or an equivalent HTTP client with synthetic data. Record the command, status, and sanitized response.
- UI/E2E work uses the visible front end as the primary evidence. Capture relevant screenshots and console/network results.
- Keep an `evidence.md` index.

## Safety rules

Every skill links here; this is the single source for these rules.

- **Secrets and data.** Remove secrets, cookies, authorization headers, personal data, account identifiers, internal endpoints, and internal-only values before displaying, posting, or committing anything. Use synthetic data.
- **AWS.** Prohibited in guided mode. In GitHub mode, an authorized issue flow may perform read-only inspection when needed. Never create, update, or delete AWS resources. Never publish AWS credentials, account identifiers, internal endpoints, or unredacted results.
- **Git and GitHub.** Never force-push, rebase, amend, or merge without an explicit request; write to GitHub only within an authorized flow.

## Quality and review

**Tests after the change.** Implement the production change, then write an automated test for every acceptance criterion in `design.md` (`AC-n`) against that AC's "how to verify" (command, page, or file plus expected result). Tests stay mandatory. Implementation is done only when all AC tests pass; a skipped or deleted AC test means not done. When an automated test is not meaningful, obtain approval for a proportionate alternative verification.

Code comments must be minimal. Add one only for a non-obvious invariant, constraint, compatibility need, security tradeoff, or performance reason.

Review follows [Agents per phase](#agents-per-phase): the reviewer is never the implementer. If the required reviewer is unavailable, do not report the review as complete. A standalone `sdlc-review` writes nothing; an SDLC feature review (guided or lane) keeps its record in the task folder as `round-<N>/` (one file per reviewer; the round closes only when all have been delivered) and a consolidated `review.md`, never committed and archived with the folder. Never resume the implementer mid-round. If the change requires a human decision (see `skills/sdlc-review/feature-review.md`), also write `decision.md` there; agents never merge. Use the `sdlc-review` skill; after corrections, run it in delta mode so follow-up reviews verify only the correction diff. Open pull requests and handle reviewer comments with `sdlc-pr`.

Use `error.md` during planning, QA, and review. A repeated failure becomes an error-catalog rule with a prevention check.

## Implementation modes

Chosen at intake and recorded as `Mode:` in `design.md`, so the owner keeps his own mental model when he wants it. In both, production work comes first; the AC tests are written afterwards against each AC's how-to-verify.

- **guided** (imperative): the implementer writes no production logic. It inserts `SDLC-PSEUDO` comment blocks at the exact places to change, with real calls and signatures from `codemap.md`, order, inputs and outputs, posts the `file:line` list and stops. The owner implements and says `pronto`; then the implementer writes the AC tests, runs checks and review. No `SDLC-PSEUDO` marker may remain before the PR (`agent-run.sh pseudo-check`).
- **auto**: the agent implements in checkpoints of about `checkpoint_lines` changed lines (default 250; `agents.yml`, overridden by `project.conf`), always at a task boundary. Each checkpoint is committed and summarized (diff, tasks done, tasks next) and waits for `segue` or feedback, which is applied first. Every checkpoint is a row in `metrics.md`.

## Agents per phase

[agents.yml](agents.yml) assigns an agent to each phase. Allowed agents: claude, codex, grok, gemini. In a lane, Claude is only the thin orchestrator (gates, comments, and push). Design, implement, QA and Goldfish go to Codex via `agent-run`; the main review is Grok.

| Phase | Default | Notes |
| --- | --- | --- |
| `design` | codex | Elephant; must be write-capable; lanes dispatch it with `agent-run` |
| `goldfish` | grok | Panel alternates `goldfish_agents` (default grok, then a fresh codex) |
| `implement` | codex | Must be write-capable |
| `review` | grok | Never the implementer |
| `tiebreak` | claude | Only when review and implementer disagree; cannot be grok or codex |
| `review_ui_ux` | codex | UI/UX lenses; may share a CLI with implement (see below) |
| `qa` | codex | Dispatched QA, fresh session |

- **An agent never reviews its own output.** `goldfish` ≠ `design`; `review` ≠ `implement`; `tiebreak` differs from both `implement` and `review`.
- **Exception: `review_ui_ux`.** It may use the same CLI as `implement` (default Codex). It still runs in a fresh read-only session with no implementer context, and never edits production code. The resolver and evals do not apply the `review ≠ implement` rule to this lens. The main `review` stays independent.
- **Tie-break is Claude** because the no-self-audit rule forbids `tiebreak` from being Grok (`review`) or Codex (`implement`). It is rare: it runs only when the reviewer and implementer disagree on a finding after one round; its verdict decides.
- **Available** = non-empty command in `agents.yml` and a known binary (`<agent>_bin` in the lane's `project.conf`, otherwise `PATH`). CLIs are never guessed: no command, no agent.
- **One fallback rule**, applied by [`scripts/resolve-agents.sh`](../scripts/resolve-agents.sh) before anything runs: `design` and `implement` must be available and listed in `write_capable`, or the run stops. `goldfish` falls back to a fresh `design`-agent process (clean context). `review` falls back to the first available agent ≠ implementer, else it is blocked. `tiebreak` falls back to the first available agent ∉ {implementer, reviewer}, else the human owner. `qa` falls back to `implement`. `review_ui_ux` is blocked if its agent is unavailable (it is allowed to equal `implement`). Never self-review for `review` or `tiebreak`.
- **Guardrails.** Lanes dispatch design, implement, review, review_ui_ux, qa, goldfish and tiebreak through `agent-run.sh`: no approvals inside the agent's sandbox (Codex `workspace-write` for design, implement and qa, `read-only` otherwise), `APOLO_SDLC_LANE`/`APOLO_SDLC_PHASE` exported, GitHub tokens removed and push disabled. Only the lane's Claude session pushes.

## Metrics

Each task keeps `project-doc/<task-id>/metrics.md`, one row appended per agent run:

| Phase | Agent | Tokens (if known) | Attempt | Result |
| --- | --- | --- | --- | --- |
| implement | codex | 41k | 2 | AC tests pass |
| review | grok | — | 1 | fail: 2 findings |

Result is pass/fail plus a few words. Before archiving the task, add one line to `INDEX.md` only if a pattern is worth keeping (for example, a phase that keeps needing retries).

## Prompt evals

When a skill, template, or `SDLC.md` changes, run [../evals/](../evals/README.md) before committing.

## Installation behavior

The managed clone is the source of truth for the shared skills, these rules, the templates, and the error catalog. The installer links `sdlc` and each skill individually and never manages global `CLAUDE.md`, `AGENTS.md`, or skills it does not own. Before creating a managed link, rename an existing managed file to `<name>-old-<timestamp>` in the same directory; skill backups go to the sibling `skills-backup/` directory so they never load as duplicate skills. Refuse existing links, paths outside expected configuration directories, and unmanaged files unless explicit replacement is authorized.
