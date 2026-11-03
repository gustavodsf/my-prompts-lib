# PR Watchdog — Steps 5–7 (reconcile, measure, record, report)

Read in full before Step 5. Rules in [SKILL.md](SKILL.md) still apply.

## Step 5 — Reconcile — on Fable, as a subagent

Spawn **one** Agent with `model: "fable"` and `subagent_type: "general-purpose"`, using
`reconciler-prompt.md` beside this file — see *The model contract*. Do not reconcile inline.

Two reasons. **Judgement is the bottleneck here** — deciding whether two differently-worded
findings are the same defect is harder than finding them was, and it is one call on ~5% of
the run's tokens, so the stronger model costs almost nothing. **And a fresh context is
cleaner** — the reconciler sees five lane reports and the ticket, not your orchestration
history.

The reconciler writes `<outDir>/summary.md` itself. Read it afterwards for your report.

**Re-reviews.** When `meta.json` has a non-empty `previousSha`, `prep.sh` has already copied
the earlier pass to `<outDir>/previous-summary.md`. That file goes to the **reconciler only**
— it is not in the lane prompt and must not be added to it. The reconciler uses it to label
Resolved / Still stands / New, never to detect. A finding exists in this pass only if this
pass's lanes found it.

If Fable is unavailable, stop and tell the user rather than
reconciling on another model — the reconciler is the one place the stronger model is worth
its cost, and a silent downgrade there is what `check-panel.sh` exists to catch.

### What the reconciler must do

Only now read all five lane files. Match findings across lanes by **file, line and claim** —
not by issue number. Two lanes describing one defect in different words is agreement; count
it once.

| Lanes agreeing | Confidence | Treat as |
|---|---|---|
| 5 of 5 | 100% | real |
| 4 of 5 | 80% | real |
| 3 of 5 | 60% | needs a human look |
| 2 of 5 | 40% | needs a human look |
| 1 of 5 | 20% | probably noise — listed, not hidden |

**Always print the percentage, never the fraction.** `40%` reads as a confidence; `2/5`
reads as a score out of five and gets misread as a severity.

**Premise cap first.** A finding whose premise no lane could verify — an AWS value, a job
that actually runs, a table holding rows — is capped at **60% regardless of lane agreement**
and can never produce `Blocked`. Five lanes making the same unverifiable inference is one
guess counted five times, not five confirmations. This is not theoretical: it produced a
false `Blocked` on a real PR. A regression claim with no citation of prior behaviour counts as
premise-derived. See `reconciler-prompt.md`.

**Absent evidence blocks.** If `ci-signal.json` shows a must-run gate skipped — **Build** or
**the test matrix** — the verdict is `Blocked — no CI evidence`, regardless of findings.
Conditional gates that skip by design (`Run Migrations` with no migrations, CDK with no infra
change) do not count. Calibrated on real PRs: Build + tests skipped blocks; only `Run Migrations` skipped
does not block.

**Verdict** — apply the standard's Phase 4 order to findings at 80% or better:

1. A spec violation at 80%+, or a Critical security finding at 80%+ in code this diff
   introduces → **Blocked**. Applies in legacy mode too.
2. Any other Critical at 80%+ → **Changes Requested**.
3. Otherwise → **Approved**.

Two amendments for five lanes:

- **A Critical at 40–60% forces at least Changes Requested.** Give the percentage.
- **A Critical at 20% does not set the verdict.** It goes in an `## Escalate` block at the
  top. One in five is inside the noise floor, but a missed security hole is not something
  to bury.

The standard has no 0–10 score table, so do not invent one. The issue list is the verdict.

An AC counts as met at 80% or better. If `ticket.md` is `UNAVAILABLE`, drop the AC table and
write the single line `Unverified — ticket not fetched`.

### The summary is negatives only

`summary.md` exists to tell someone what is wrong with the PR. The five lane files are the
full record — do not duplicate them.

**Cut before writing:**

- Strengths, near-misses, and what the PR got right.
- The per-lane verdict table. Nobody acts on it.
- Style and consistency findings: optional-chaining, naming, one pattern versus another,
  formatting. Even at 100%. Lane agreement tracks how *obvious* a finding is, not how much
  it *matters* — a nit five lanes spot is still a nit.
- A "dropped as nits" section. Do not list what you cut.
- The merged PR-description block, edge cases, and untested-path inventory.

**Keep only** a finding that changes what someone does next: wrong behaviour, a test that
cannot fail, an unproven claim, a missing guard, an unmet AC.

**Every finding carries a one-line fix.** A problem with no proposed fix is half a finding.

### Format — bullets and tables, no paragraphs

- Bullets and tables only. No prose paragraphs anywhere.
- One fact per bullet. One line on screen.
- Lead with the thing, not the setup.
- `file:line` on every finding.
- Bold the value a reader must see: **`NaN`**, **always `false`**.
- Under ~100 lines. If it runs longer, findings are being padded.

**Both output templates live in `output-format.md`** beside this file; `prep.sh` copies it
into the bundle as `format.md` and the reconciler is pointed at that path. Keeping them out of
this file means the output can change without editing the orchestrator, and the reconciler
follows a format it can actually open.

The reconciler writes two files: `summary.md` (negatives only, worst first) and `detail.md`
(the full record, including what was cut and why). Step 6 gates on both.

## Step 5b — Measure

```bash
~/.claude/skills/pr-watchdog/scripts/metrics.sh <outDir>
```

Reads the harness transcripts and writes `<outDir>/metrics.json`: real input, output, and
cache tokens per lane, wall seconds, tool-call counts, and the phase markers each lane
emitted. Never take a lane's word for its own usage — a subagent has no token counter, so
a self-reported figure is invented.

Add your own orchestration cost to the summary as a separate line. `lanesTotal.wallSeconds`
is summed, not elapsed — the lanes ran concurrently, so quote elapsed separately.

**Per-category tokens are not attributable.** The transcript segments by turn, not by review
category, and one turn often spans several. Phase markers give per-phase *time* and *turn
count* honestly; do not divide tokens across categories and present the result as measured.

## Step 5c — CI signal health

```bash
~/.claude/skills/pr-watchdog/scripts/ci-signal.sh report
```

`finish.sh` records every review's gate counts to `~/dev/.pr-watchdog/ci-signal.json`.
This step reads the streak.

The watchdog cannot run tests, so CI is its only evidence the code works — and when a gate
silently skips, "nothing failed" and "nothing ran" look identical in `checks.txt`. A single
PR with skipped gates is a footnote. **Three consecutive reviews with every build and test
gate skipped is a broken pipeline**, and no per-PR summary can see that.

If `verdict` says `PIPELINE SUSPECT`, put it at the top of your report to the user, above
the PR findings. A watchdog gating `test` on a pipeline that proves nothing is the more
serious problem.

Measured 2026-08-26: one PR skipped 5 of 5 gates, while two others skipped 0–1 of 14.
So the failure is intermittent, not constant — consistent with a label race at gate
evaluation time rather than a permanently broken workflow.

## Step 5d — Validate the panel

```bash
~/.claude/skills/pr-watchdog/scripts/check-panel.sh <outDir>
```

Refuses a run that is not five lanes on the right models. Checks all five lane files exist
and are non-empty, that no sixth lane appeared, and that `models.json` records `opus` lanes
and a `fable` reconciler.

**If it fails, say so at the top of your report and do not present the agreement percentages
as confidence.** Four lanes and five lanes produce numbers that look identical and mean
different things, and nothing in `summary.md` distinguishes them. `finish.sh` runs this too
and will refuse to record the run.

## Step 6 — Record

```bash
~/.claude/skills/pr-watchdog/scripts/finish.sh <pr-number> <sha>
```

Only after `check-panel.sh` passes and `summary.md` and `detail.md` both exist. Stamps the
SHA into `state.json` and removes the worktree, so the next run skips this PR until someone
pushes. Then loop to Step 2.

## Step 7 — Report

One table across the PRs handled: PR, ticket, mode, verdict, real problems, AC met, path to
`summary.md`. Then `## Actions for you` — only PRs with a Critical at 80%+, an escalated 20%
Critical, or an unmet acceptance criterion, most blocking first.

Percentages in chat too, never fractions.

Do not paste full reviews into chat. The files are the deliverable.
