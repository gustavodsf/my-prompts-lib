# PR Watchdog — Steps 5–7 (reconcile, measure, record, report)

Read in full before Step 5. Rules in [SKILL.md](SKILL.md) still apply.

## Step 5 — Reconcile — you, the orchestrator

Apply `reconciler-prompt.md` beside this file in this session and write `<outDir>/summary.md`
yourself. Do not spawn a Fable (or any other) subagent to reconcile. See *The model contract*.

With one or two short lane reports, a separate expensive model is not worth it. Stay on the
ticket, the lane files and the CI signal; do not lean on earlier orchestration chatter when
deciding whether two wordings are the same defect.

**Re-reviews.** When `meta.json` has a non-empty `previousSha`, `prep.sh` has already copied
the earlier pass to `<outDir>/previous-summary.md`. That file goes to the **reconciler only**
— it is not in the lane prompt and must not be added to it. The reconciler uses it to label
Resolved / Still stands / New, never to detect. A finding exists in this pass only if this
pass's lanes found it.

### What the reconciler must do

Only now read the lane files (`lane-codex.md` and/or `lane-grok.md`). Match findings across
lanes by **file, line and claim** — not by issue number. Two lanes describing one defect in
different words is agreement; count it once.

| Lanes agreeing | Treat as |
|---|---|
| 2 of 2 | confirmed |
| 1 of 2 | a lead, not a verdict |
| 1 of 1 (single-lane run) | a lead — no agreement confidence |

State the count as `2/2` or `1/2`, not a percentage calibrated on five Opus lanes.

**Premise cap first.** A finding whose premise no lane could verify — an AWS value, a job
that actually runs, a table holding rows — is capped at **60% regardless of lane agreement**
and can never produce `BLOCKED`. Two lanes making the same unverifiable inference is one
guess counted twice, not two confirmations. This is not theoretical: it produced a
false `BLOCKED` on a real PR. A regression claim with no citation of prior behaviour counts as
premise-derived. See `reconciler-prompt.md`.

**Absent evidence blocks.** If `ci-signal.json` shows a must-run gate skipped — **Build** or
**the test matrix** — the verdict is `BLOCKED — no CI evidence`, regardless of findings.
Conditional gates that skip by design (`Run Migrations` with no migrations, CDK with no infra
change) do not count. Calibrated on real PRs: Build + tests skipped blocks; only `Run Migrations` skipped
does not block.

**Verdict** — apply the standard's Phase 4 order to **confirmed** (`2/2`) findings only:

1. A confirmed spec violation, or a confirmed Critical security finding in code this diff
   introduces → **BLOCKED**. Applies in legacy mode too.
2. Any other confirmed Critical → **CHANGES**.
3. Otherwise → **PASS**.

- **A Critical lead (`1/2` or `1/1`) does not set the verdict.** It goes in an `## Escalate` block at the
  top. One of two is not confirmation, but a missed security hole is not something to bury.

The standard has no 0–10 score table, so do not invent one. The issue list is the verdict.

An AC counts as met when both lanes (or the only lane, noted as unverified agreement) say it is met. If `ticket.md` is `UNAVAILABLE`, drop the AC table and
write the single line `Unverified — ticket not fetched`.

### The summary is negatives only

`summary.md` exists to tell someone what is wrong with the PR. The lane files are the
full record — do not duplicate them.

**Cut before writing:**

- Strengths, near-misses, and what the PR got right.
- The per-lane verdict table. Nobody acts on it.
- Style and consistency findings: optional-chaining, naming, one pattern versus another,
  formatting. Even at 100%. Lane agreement tracks how *obvious* a finding is, not how much
  it *matters* — a nit both lanes spot is still a nit.
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

Refuses a run that is not 1–2 Codex/Grok lanes with reconciler orchestrator. Checks the lane files exist
and are non-empty, that only `lane-codex.md` and/or `lane-grok.md` appeared, and that
`models.json` records those CLIs and `reconciler: "orchestrator"`.

**If it fails, say so at the top of your report and do not present the agreement counts
as confidence.** `finish.sh` runs this too and will refuse to record the run.

## Step 6 — Record

```bash
~/.claude/skills/pr-watchdog/scripts/finish.sh <pr-number> <sha>
```

Only after `check-panel.sh` passes and `summary.md` and `detail.md` both exist. Stamps the
SHA into `state.json` and removes the worktree, so the next run skips this PR until someone
pushes. Then loop to Step 2.

## Step 7 — Report

One table across the PRs handled: PR, ticket, mode, verdict, real problems, AC met, path to
`summary.md`. Then `## Actions for you` — only PRs with a confirmed Critical, an escalated Critical lead,
or an unmet acceptance criterion, most blocking first.

Use `2/2` and `1/2` in chat, not percentages from the old five-lane scale.

Do not paste full reviews into chat. The files are the deliverable.
