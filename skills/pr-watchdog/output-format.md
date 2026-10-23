# Output format — the two files the reconciler writes

**This file is the single source for both templates.** `prep.sh` copies it into every
bundle as `format.md`, so a run always writes the format current when it started, even if
someone edits this file mid-run. The reconciler reads `{{OUTDIR}}/format.md`; nothing else
should carry a copy of these templates.

Both files are written every run. `summary.md` is what gets read. `detail.md` is what gets
checked when someone disputes the verdict.

---

Write `<outDir>/summary.md`:

```markdown
---
pr: <n>
ticket: TECH-####
sha: <short>
title: <pr title>
author: <login>
verdict: Approved | Changes Requested | Blocked
mode: STRICT | LEGACY
specCompliance: <met>/<total> | Unverified
realProblems: <count>
knownUnfixed: <count>
reviewedAt: <UTC timestamp>
---

# PR <n> — problems only

- **<scope of the diff in one bullet>**
- **<the honest ceiling — e.g. nothing here is a shipped bug, or: this breaks X>**

## Since last pass
(omit entirely when there is no previous-summary.md)

- **Resolved**: <finding from the previous pass, and what in the code fixes it>
- **Still stands**: <found again independently this pass>
- **New**: <this pass only, including anything the fix introduced>
- **Dropped — not re-raised**: <previous finding no lane raised, no fix visible>

## Escalate — 1 of 5 lanes, but Critical
(omit if none)

## Unmet acceptance criteria
**Source**: <ClickUp TECH-#### | local spec | Unverified — ticket not fetched>

| AC | Status | Lanes | Evidence (file:line) |
|---|---|---|---|

(only ACs agreed met by fewer than 4 lanes. Omit the section when all are met — say so in
the header bullets.)

## The <n>

| # | Problem | Location | Lanes |
|---|---|---|---|

### <n>. <problem as a claim, not a category>
- <bullets: mechanism, then the concrete failure>
- <`file:line` — input → wrong result>

**Fix**: <one line>

(repeat per finding, worst first)

## Not covered
- <areas the diff touches that no lane engaged with — migrations, money, auth, high-volume
  tables. Voting cannot catch a miss; this section is the only place it surfaces.>
(write `None` if every touched area was engaged)

## Known unfixed leaks
<omit if none. Anything the ticket parks as a follow-up but that still bites.>

| Location | Problem | Fix |
|---|---|---|

## CI
- <failed or pending checks, worst first>
- <tests, lint and typecheck not run locally>

```

The findings are already ordered worst-first. Do not add a closing section that re-lists them
in priority order — it restates what the reader just read and adds nothing.

### The full record — `detail.md`

Write `<outDir>/detail.md` **as well**, every run. `summary.md` is what gets read; this is
what gets checked when someone disputes it. We are still tuning the lane count, the
thresholds and the nit boundary, so the evidence that a finding was cut — or kept — has to
survive.

Nothing is cut from `detail.md`. It carries what `summary.md` deliberately drops.

```markdown
---
pr: <n>
ticket: TECH-####
sha: <short>
verdict: <same as summary.md>
mode: STRICT | LEGACY
reviewedAt: <UTC timestamp>
---

## Lane votes

| Lane | Mode | Verdict | Criticals | Warnings | Spec |
|---|---|---|---|---|---|
| a | | | | | |
(b–e)

## Acceptance criteria — all of them
**Source**: <ClickUp TECH-#### | local spec | Unverified — ticket not fetched>

| AC | Met? | Lanes | Evidence (file:line) |
|---|---|---|---|

## Findings by lane count

### 5 of 5 and 4 of 5
| Sev | Location | Finding | Why it breaks | Lanes |
|---|---|---|---|---|

### 3 of 5 and 2 of 5
| Sev | Location | Finding | Lanes |
|---|---|---|---|

### 1 of 5
| Sev | Location | Finding | Lane |
|---|---|---|---|

## Cut from summary.md
<every finding held back, with its lane count and one line on why it was cut. This section
is the tuning signal — a nit that keeps resurfacing at 5 of 5 means the boundary is wrong.>

## Needs a decision record
- `file:line` — <the question, and the lane count>

## Where the lanes disagreed
- <same code, opposite reads, and what a human should check>

## Strengths and near-misses
- <what the PR got right, and what it nearly got wrong. Named specifically — this is how
  you tell a careful lane from a lazy one when auditing the run.>

## For the PR description
<merge the lanes' PR-description blocks. Keep an edge case only when 4+ lanes found it. Keep every
untested path any lane found — that section is mechanical, so a lane finding one the others
missed is a hit, not noise. Empty sections read `None`.>

## CI
- <every check, pass/fail/pending, plus: tests/lint/typecheck not run locally>
```
