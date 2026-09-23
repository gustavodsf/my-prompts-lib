# PR Watchdog — what this is

Two skills. One reviews a diff; the other runs that review five times and reconciles the
results.

| Skill | Does | Read it if you want to know |
|---|---|---|
| **`watchdog-review`** | Reviews one diff to the DeliverThat standard | **what "reviewed" means.** This is the standard itself — 307 lines, and the only place review behaviour is defined. |
| **`pr-watchdog`** | Watches GitHub, runs five isolated reviews per PR, reconciles them | how confidence is produced, and what stops it costing too much |

**Version**: `pr-watchdog` 2.0.0 · `watchdog-review` 1.0.0 · 27 Aug 2026 · Phase 1

## If you have two minutes

Read **`watchdog-review/SKILL.md`**, the section headed *The bar for a finding*:

> A named failure scenario, or it is not a candidate. A verify label, or it is not a
> finding. A `file:line`, or it is not reportable.

Everything else is machinery around that bar.

## If you have twenty

1. **`watchdog-review/SKILL.md`** — the four phases: find → verify → sweep → classify. Note
   Phase 2: every candidate is labelled CONFIRMED, PLAUSIBLE or REFUTED, and REFUTED ones are
   dropped rather than downgraded into the report.
2. **`pr-watchdog/SKILL.md`** Step 5 — how five independent reports become one verdict, and
   why a finding nobody could verify caps at 60% and cannot block.
3. **`pr-watchdog/SKILL.md`** *Cost model* — why cost is context × turns, and the four gates.

## Three ways to run it

| Command | Reviews | Reviewers |
|---|---|---|
| `/watchdog-review` | your branch | one — you, reading the standard |
| **`/pr-watchdog --local`** | **your uncommitted work** | **five, with agreement percentages** |
| `/pr-watchdog` (or the hourly routine) | an open PR | five |

The middle one is the point of having a standard rather than a tool: the same five-lane
verdict, before the PR exists, on work that is still on your machine.

## What it does, plainly

- **Five reviewers, not one.** Identical prompts, isolated contexts, no visibility of each
  other. Confidence is how many independently agreed: 100% = five, 80% = four, down to 20%.
- **Reviews against the ticket**, not just the code. Clean code that does not do what the
  ticket asked is a spec failure.
- **Three axes on every finding** — severity (impact), verify label (is the mechanism real),
  agreement (how many reviewers reached it). Collapsing them into one number loses
  information, so it doesn't.

## What it does not do

- **Cannot run tests.** No credentials, deliberately, so it runs unattended. CI results stand
  in, and a skipped required gate is reported as a finding rather than treated as a pass.
- **Cannot verify some premises.** Anything resting on a value in an environment, a job that
  actually ran, or a table holding rows is capped and carries the command that would settle
  it. This rule exists because five reviewers once blocked a legitimate PR on one shared
  unverifiable assumption.
- **Recall is unmeasured.** It finds real problems and filters its own noise. What it *misses*
  has not been measured — that needs the calibration run described in
  `pr-watchdog/SKILL.md` under *Backwards mode*.

## Where it came from

Not written from scratch. Assembled from work that already existed and was already trusted:

- **Monorepo `flow-review` 2.4.0** — the four-phase pipeline, 3-state verify, the sweep, and
  the PLAUSIBLE-by-default calibration. Its authors flagged these as improvements that should
  travel back to Delivery-API; this is that.
- **Anthropic's `code-review` plugin** (Boris Cherny) — the history, prior-PR and
  comment-contract finders, and the false-positive list.
- **Brendan Glancy** — the analysis of PR 3019, which produced the premise caps, plus seven
  error-handling fixes including a silent-corruption path where a `gh` failure wrote its error
  message into the file lanes read as CI results.
- **Delivery-API `review` / `review-pr`** — the strict/legacy module severity model.

## How it improves

`watchdog-review/SKILL.md` is the tuning mechanism. Engineers run `/watchdog-review` on their
own branch before opening a PR; when a rule misfires on their work, they fix the rule. Both
callers — the engineer and the watchdog's lanes — read the same file, so a change lands
everywhere at once.

Phase 2 adds the Unified Context Vault and a calibration corpus, which will recommend changes
to this file from measured misses rather than opinion.

Setup and prerequisites: `INSTALL.md`.
