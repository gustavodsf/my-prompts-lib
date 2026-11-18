---
name: pr-watchdog
description: Watch the Delivery-API GitHub repo for new or updated pull requests, pull each PR's ClickUp ticket for its acceptance criteria, review the PR with 1–2 independent Codex/Grok lanes running the team-owned review standard, and reconcile their votes into one summary. Use when asked to run the PR watchdog, check for new PRs to review, sweep open PRs, or set up recurring PR review. Triggers on "pr watchdog", "watchdog", "check for new PRs", "review the open PRs", "sweep the PRs", "any new PRs to review".
argument-hint: "[PR number | --local | --limit N | --all | --reset]"
allowed-tools: Bash, Read, Write, Grep, Glob
version: 3.0.0
---

# PR Watchdog

One or two independent lanes review the same PR with the **`sdlc-review` standard** (copied into each bundle as `review/SKILL.md`) and against the
**acceptance criteria on its ClickUp ticket**. Two of two agreeing makes a finding
confirmed. One of two makes it a lead, not a verdict. A single-lane run has no agreement
confidence — report its findings as that one reviewer's leads.

Lineage: [lineage.md](lineage.md). Historical five-Opus / Fable notes there and in
`calibration.md` are history, not the current contract.

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
- **Lanes are Codex and/or Grok CLIs, never five Opus Agent spawns and never Fable.**

## The model contract

**One table. Every spawn in this skill is covered by it, and nothing else in this file
overrides it.**

| Role | Count | Who | Set how | If it is wrong |
|---|---|---|---|---|
| Review lane | 1–2 | **Codex and/or Grok** | Fresh read-only CLI process; files `lane-codex.md` / `lane-grok.md` | `check-panel.sh` refuses the run |
| Reconciler | 1 | **orchestrator** | You apply `reconciler-prompt.md` in this session; do not spawn Fable | `check-panel.sh` refuses the run |
| Orchestrator (you) | 1 | whatever the session is | not settable | Nothing — it does not judge until Step 5 |

Run both CLIs when both are available. If only one is available, run that one and say so.
Do not spawn Claude Agent lanes to stand in for a missing CLI.

## Layout

| Path | Holds |
|---|---|
| `~/dev/.pr-watchdog/state.json` | last reviewed head SHA per PR |
| `~/dev/.pr-watchdog/worktrees/pr-<n>/` | throwaway checkout of the PR head |
| `~/dev/.pr-watchdog/reviews/PR-<n>/<sha>/` | bundle, ticket, historical evidence, lane files, summary |

Scripts in `scripts/`: `scan.sh`, `prep.sh`, `context.sh`, `metrics.sh`, `finish.sh`,
`reset.sh`, plus `corpus.sh` and `ground-truth.sh` for calibration.

`context.sh` runs inside `prep.sh` and gathers the historical evidence **once** for every
lane: blame for the changed hunks, prior PRs that touched the same files with their
reviewer comments, and recent file history. Lanes each judge that evidence independently,
but none of them re-runs the git and gh calls.

## Procedure — load the step file before acting

This file holds the rules, the contract and the layout. The procedure lives in files beside it; read each one **in full** at the point shown. Do not run a step from memory.

| When | Read |
|---|---|
| `--local` | [local-mode.md](local-mode.md) |
| Steps 1–4b: scan, prep, eligibility gate, ticket fetch, 1–2 lanes, model record | [steps-prep.md](steps-prep.md) |
| Steps 5–7: reconcile, measure, CI signal, panel validation, record, report | [steps-reconcile.md](steps-reconcile.md) |
| Reconciler and summary templates | [reconciler-prompt.md](reconciler-prompt.md), [output-format.md](output-format.md) |
| Lane prompt | [lane-prompt.md](lane-prompt.md) |
| Cost tuning, `--all` backwards calibration | [calibration.md](calibration.md) |
| Where the standard came from | [lineage.md](lineage.md) |
