---
name: sdlc-review
description: Review a diff to the DeliverThat engineering standard — find candidates, verify each one, sweep for gaps, classify. Every finding carries a named failure scenario, a file:line, and a CONFIRMED/PLAUSIBLE verify label. Use when reviewing a branch or PR before opening it, checking your own changes, running the SDLC final or follow-up feature review, or asking "would the watchdog flag this". Also the standard the PR Watchdog's five lanes run. Triggers on "review this", "review my branch", "check my changes", "watchdog review", "would this pass review", "final review".
argument-hint: "[task identifier or issue number]"
version: 1.1.0
---

# SDLC Review

**SDLC feature review:** when this skill is invoked to review an approved feature or a correction cycle, follow [feature-review.md](feature-review.md) beside this file. It orchestrates the reviewers; each reviewer applies the standard below. A pr-watchdog lane ignores this paragraph.

Only in lane mode (see [../../sdlc/lane-mode.md](../../sdlc/lane-mode.md) for when it is active), also apply that file; in every other session, including pr-watchdog lanes, ignore it.

**This file is the review standard**, run by `/sdlc-review` on your own branch and by the PR Watchdog's five lanes. Callers and lineage: [lineage.md](lineage.md).

## Scope — establish your inputs first

This file runs in two places and the inputs arrive differently. **Work out which you are in
before Phase 1**, then read the right column throughout.

**Three callers**, not two: `/sdlc-review` (you, one reviewer), `/pr-watchdog --local`
(five lanes on your working tree — bundle paths apply, `ciAvailable: false`), and a watchdog
lane on an open PR. The two bundle-backed callers read the right-hand column.

| Input | Standalone (`/sdlc-review`) | Watchdog lane or `--local` |
|---|---|---|
| **The diff** | `git diff origin/test...HEAD` — plus `git diff HEAD` if you have uncommitted work, and say which you reviewed. Exclude `prisma/generated`, lockfiles and build output. | `diff.patch` — generated output already excluded by `prep` |
| Changed files | `git diff origin/test...HEAD --name-status` | `files.txt` |
| **Acceptance criteria** | Ticket ID from the branch name (`PROJ-1234/...` → `PROJ-1234`). Fetch it: `ToolSearch` for `+clickup get_task`, then `clickup_get_task` with `include: ["description","checklists","subtasks"]` — use `markdown_description`, and note ACs sit in the description as `- [ ]`, not in `checklists`. No ticket ID → say so and score spec compliance `Unverified`. | `ticket.md`, already fetched |
| CI results | `gh pr checks <n>` if a PR exists; otherwise "no PR yet" | `checks.txt` |
| Blame on replaced lines | `git blame origin/test -L<start>,<end> -- <file>` on replaced hunks only | `blame.txt` |
| Prior PRs on these files | `git log --merges -n 20 --format='%s' -- <file>` → extract `#NNNN` → `gh pr view NNNN --comments`, cap ~3 | `prior-prs.json` |
| Repo conventions | The live `CLAUDE.md`, `.claude/rules/`, `specs/standards/` | `checklist/` (snapshotted from `test`) |

**Standalone, start by stating the scope in one line** — base, head, whether uncommitted work
is included, and the ticket — so the reader knows what was reviewed. Then run all four phases.

**Standalone, write nothing.** Report in the conversation. Do not create a review file, do not
commit, do not post to GitHub, do not touch the ticket.

Everything below is caller-agnostic. Where it names a bare filename (`blame.txt`,
`prior-prs.json`), that is the lane's copy — standalone, substitute the command above.

## The bar for a finding

**A named failure scenario, or it is not a candidate.** Inputs or state → wrong output,
crash, or violated acceptance criterion. Named, not gestured at.

**A verify label, or it is not a finding.** Phase 2 assigns it.

**A `file:line`, or it is not reportable.** For a broken caller, the caller's line.

## What you cannot do, and what stands in for it

**When the watchdog runs this**, there are no credentials and the app cannot run. That is
deliberate — it lets the watchdog run unattended — but it means some premises behind findings
are uncheckable.

**When you run it yourself**, you can check them: run the test, query the parameter, read the
log. Do that instead of capping the finding, and say what you ran.

| Cannot | Use instead |
|---|---|
| Run tests, lint, typecheck | `checks.txt` — CI results |
| Reach AWS, databases, prod config | Nothing. Name the premise (see Phase 2). |
| `npm install` | Read the code; `node_modules` is not installed |

**A skipped required check is a finding, not an absence.** Name the gate. "Nothing failed" is
not "everything passed."

---


## The standard continues in files beside this one — read them

These files are part of the standard, not optional detail. They travel with this directory into every watchdog bundle (`review/`).

1. [phases.md](phases.md) — Phase 1 find candidates, Phase 2 verify (calibration, convention quotes, framework mitigations, premise caps), Phase 3 sweep, Phase 4 classify and what is not a finding. Read in full before Phase 1.
2. [output.md](output.md) — reading cheaply, and the exact output sections (spec compliance, issues by severity, test review, not covered). Read before writing.
3. [security-checklist.md](security-checklist.md) — used in Phase 1.
4. [lineage.md](lineage.md) — who calls this file and where its rules came from. Improve review quality by improving these files.
