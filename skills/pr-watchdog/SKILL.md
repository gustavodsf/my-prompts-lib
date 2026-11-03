---
name: pr-watchdog
description: Watch the Delivery-API GitHub repo for new or updated pull requests, pull each PR's ClickUp ticket for its acceptance criteria, review the PR with five independent agentic lanes running the team-owned review standard, and reconcile their votes into one summary. Use when asked to run the PR watchdog, check for new PRs to review, sweep open PRs, or set up recurring PR review. Triggers on "pr watchdog", "watchdog", "check for new PRs", "review the open PRs", "sweep the PRs", "any new PRs to review".
argument-hint: "[PR number | --local | --limit N | --all | --reset]"
allowed-tools: Bash, Read, Write, Grep, Glob, Agent
model: opus
version: 2.4.0
---

# PR Watchdog

Five independent lanes review the same PR with the **`sdlc-review` standard** (copied into each bundle as `review/SKILL.md`) and against the
**acceptance criteria on its ClickUp ticket**. Four of five agreeing makes a finding
confirmed. Fewer than that makes it a lead, not a verdict.

Lineage: [lineage.md](lineage.md).

## Hard rules

- **Local only. Nothing is posted anywhere.** No `gh pr comment`, `pr review`, `pr edit`,
  `pr merge`, `pr close`, no writing `gh api` calls, and no ClickUp writes — reading the
  ticket is the only ClickUp action permitted.
- **Never open a PR, never push, never commit.** The watchdog produces files. Publishing
  is the user's decision, in a separate message.
- **Never run inside the user's main checkout.** All work happens in throwaway worktrees
  under `~/dev/.pr-watchdog/worktrees/`, so `git status` in `~/dev/Delivery-API` stays clean.
- **Never `npm install`.** `node_modules` is ~1GB. CI is the test and lint signal.
- **Never write into the repo** — no `.claude/reviews/`, no `.claude/learnings/`, no
  `CLAUDE.md` edits. Lanes write only their own bundle file.
- **Never run tests, lint, or typecheck.** We cannot, so CI
  from `gh pr checks` is the signal and lanes must say so out loud.
- **Every lane is spawned with `model: "opus"`, explicitly, on every call. No exceptions.**
  A spawn without it inherits the calling session's model. Run this from a Fable session and
  you get six Fable agents instead of five Opus and one Fable — several times the cost, with
  nothing in the output to show it. **If you are about to spawn a lane and have not typed
  `model: "opus"`, stop.**

## The model contract

**One table. Every spawn in this skill is covered by it, and nothing else in this file
overrides it.**

| Role | Count | Model | Set how | If it is wrong |
|---|---|---|---|---|
| Review lane | 5 | **`opus`** | `model: "opus"` on every Agent call | `check-panel.sh` refuses the run |
| Reconciler | 1 | **`fable`** | `model: "fable"` on the Agent call | `check-panel.sh` refuses the run |
| Orchestrator (you) | 1 | whatever the session is | not settable | Nothing — it does not judge |

**Why five Opus and not five Fable.** The panel exists to reduce variance, and five samples
is what does that. Fable costs several times more per token and does not buy more variance,
so a Fable panel is the same result for multiples of the price. The agreement thresholds
were calibrated on five Opus.

**Why Fable for the reconciler.** Deciding whether two differently-worded findings are the
same defect is the hardest judgement in the run, and it is one call on roughly 5% of the
run's tokens. The stronger model costs almost nothing there.

**Effort level cannot be pinned per spawn.** The Agent tool takes a model, not an effort.
Spawned lanes inherit the session's effort setting, so a run started on high effort produces
five high-effort Opus lanes. **If effort matters for a run, the operator sets it on their
session before starting** — it is the one thing here the skill cannot control. Opus at
medium is the intended setting.

**The session model is irrelevant to the lanes.** Pin the model on each call and a Fable
session produces a correct panel. Never switch your session to work around a block.

## Layout

| Path | Holds |
|---|---|
| `~/dev/.pr-watchdog/state.json` | last reviewed head SHA per PR |
| `~/dev/.pr-watchdog/worktrees/pr-<n>/` | throwaway checkout of the PR head |
| `~/dev/.pr-watchdog/reviews/PR-<n>/<sha>/` | bundle, ticket, historical evidence, five lane files, summary |

Scripts in `scripts/`: `scan.sh`, `prep.sh`, `context.sh`, `metrics.sh`, `finish.sh`,
`reset.sh`, plus `corpus.sh` and `ground-truth.sh` for calibration.

`context.sh` runs inside `prep.sh` and gathers the historical evidence **once** for all five
lanes: blame for the changed hunks, prior PRs that touched the same files with their
reviewer comments, and recent file history. Lanes each judge that evidence independently —
which is where the five-way confidence comes from — but none of them re-runs the git and gh
calls. Same accuracy, a fifth of the fetching.


## Procedure — load the step file before acting

This file holds the rules, the contract and the layout. The procedure lives in files beside it; read each one **in full** at the point shown. Do not run a step from memory.

| When | Read |
|---|---|
| `--local` | [local-mode.md](local-mode.md) |
| Steps 1–4b: scan, prep, eligibility gate, ticket fetch, five lanes, model record | [steps-prep.md](steps-prep.md) |
| Steps 5–7: reconcile, measure, CI signal, panel validation, record, report | [steps-reconcile.md](steps-reconcile.md) |
| Reconciler and summary templates | [reconciler-prompt.md](reconciler-prompt.md), [output-format.md](output-format.md) |
| Lane prompt | [lane-prompt.md](lane-prompt.md) |
| Cost tuning, `--all` backwards calibration | [calibration.md](calibration.md) |
| Where the standard came from | [lineage.md](lineage.md) |
