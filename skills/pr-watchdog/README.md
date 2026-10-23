# PR Watchdog — what this is

Two skills. One reviews a diff; the other runs that review five times and reconciles the
results.

| Skill | Does | Read it if you want to know |
|---|---|---|
| **`sdlc-review`** | Reviews one diff to the DeliverThat standard | **what "reviewed" means.** This is the standard itself — 307 lines, and the only place review behaviour is defined. |
| **`pr-watchdog`** | Watches GitHub, runs five isolated reviews per PR, reconciles them | how confidence is produced, and what stops it costing too much |

**Version**: `pr-watchdog` 2.4.0 · `sdlc-review` standard 1.1.0

## If you have two minutes

Read **`sdlc-review/SKILL.md`**, the section headed *The bar for a finding*:

> A named failure scenario, or it is not a candidate. A verify label, or it is not a
> finding. A `file:line`, or it is not reportable.

Everything else is machinery around that bar.

## If you have twenty

1. **`sdlc-review/SKILL.md`** — the four phases: find → verify → sweep → classify. Note
   Phase 2: every candidate is labelled CONFIRMED, PLAUSIBLE or REFUTED, and REFUTED ones are
   dropped rather than downgraded into the report.
2. **`SKILL.md`** Step 5 — how five independent reports become one verdict, and
   why a finding nobody could verify caps at 60% and cannot block.
3. **`SKILL.md`** *Cost model* — why cost is context × turns, and the four gates.

## Three ways to run it

| Command | Reviews | Reviewers |
|---|---|---|
| `/sdlc-review` | your branch | one — you, reading the standard |
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
  `SKILL.md` under *Backwards mode*.

## Where it came from

Not written from scratch. Assembled from work that already existed and was already trusted:

- **Monorepo `flow-review` 2.4.0** — the four-phase pipeline, 3-state verify, the sweep, and
  the PLAUSIBLE-by-default calibration. Its authors flagged these as improvements that should
  travel back to Delivery-API; this is that.
- **Anthropic's `code-review` plugin** (Boris Cherny) — the history, prior-PR and
  comment-contract finders, and the false-positive list.
- **Team incident analysis** — of a PR blocked on one shared unverifiable premise, which produced the premise caps, plus seven
  error-handling fixes including a silent-corruption path where a `gh` failure wrote its error
  message into the file lanes read as CI results.
- **Delivery-API `review` / `review-pr`** — the strict/legacy module severity model.

## How it improves

`sdlc-review/SKILL.md` is the tuning mechanism. Engineers run `/sdlc-review` on their
own branch before opening a PR; when a rule misfires on their work, they fix the rule. Both
callers — the engineer and the watchdog's lanes — read the same file, so a change lands
everywhere at once.

Phase 2 adds the Unified Context Vault and a calibration corpus, which will recommend changes
to this file from measured misses rather than opinion.

## Setup

`pr-watchdog` ships with this repository as `skills/pr-watchdog/` and is invoked as `/pr-watchdog`. The installer links each repository skill into Claude Code and Codex:

```bash
./scripts/install.sh --local
```

The review standard the lanes run is the `sdlc-review` skill in this repository; the installer links it beside `pr-watchdog`, and `prep.sh` finds it there. `WATCHDOG_REVIEW_SKILL` still overrides the location.

**Run `/sdlc-review` on your own branch before you open a PR.** Same rules the watchdog
will apply, so nothing in its summary should surprise you — and if a rule misfires on your
work, fix the rule. That file is the tuning mechanism; it improves by being used.

Every path in `scripts/` resolves from `$HOME`, so no editing is needed if your repo sits
at `~/dev/Delivery-API`. Otherwise export overrides in your shell profile:

```bash
export WATCHDOG_REPO="$HOME/code/Delivery-API"
export WATCHDOG_WS="$HOME/code/.pr-watchdog"
```

Set your ClickUp workspace ID so ticket links in the bundle and the Chrome fallback resolve:

```bash
export WATCHDOG_CLICKUP_WORKSPACE=<your-workspace-id>
```

Requires `gh` (authenticated), `jq`, and `git`. Nothing else — no `npm install`.

Check it:

```bash
~/.claude/skills/pr-watchdog/scripts/scan.sh | jq length
```

That prints how many open PRs are pending review. It writes nothing.

## The hourly routine — you have to create your own

Scheduled tasks live in `~/.claude/scheduled-tasks/<id>/SKILL.md` on one machine. They are
not part of the skill and do not travel with it. Ask Claude Code:

> Create a scheduled task called pr-watchdog that runs hourly and invokes the pr-watchdog
> skill with `--limit 1`.

Then check `~/.claude/scheduled-tasks/pr-watchdog/SKILL.md` for absolute paths — the task
prompt is written with the author's home directory baked in. Swap them for yours.

The task only fires while Claude Code is open. If it is closed when the task is due, it runs
on next launch.

## What it does and does not touch

| Never | Only |
|---|---|
| Posts to GitHub, comments on PRs, pushes, opens PRs | Reads via `gh` |
| Writes to ClickUp | Reads the ticket |
| Touches your working tree or `node_modules` | Throwaway worktrees under `$WATCHDOG_WS` |
| Writes `.claude/reviews/` or `.claude/learnings/` | Files under `$WATCHDOG_WS/reviews/` |
| Runs tests, lint, or typecheck | Reads `gh pr checks` |

Output lands in `$WATCHDOG_WS/reviews/PR-<n>/<sha>/` — five `lane-*.md` files and a
reconciled `summary.md`. Read the summary; the lane files are the evidence behind it.

## The ticket fetch

Acceptance criteria come from ClickUp, and the watchdog fetches them **once** so all five
lanes assess the same requirements. Two paths:

- **ClickUp MCP** — preferred, works unattended. Needs `mcp__clickup__*` connected.
- **Claude in Chrome** — fallback. Needs Chrome open and logged into ClickUp, so it does
  not work on an unattended hourly run.

Without either, lanes mark Spec Compliance `Unverified — ticket not fetched`. They will not
guess acceptance criteria from the PR body.

## The review standard

`sdlc-review/SKILL.md` is the single review standard — four phases, all checks, verify labels,
classification and output format. It is **meant to be edited by the engineering team**: that
file is the tuning mechanism for review quality, and there is nowhere else to change it.

Its one dependency is `security-checklist.md` beside it. `prep.sh` copies both into each
bundle, so a run always reviews against the version current when it started even if someone
edits the skill mid-run. Override the location with `WATCHDOG_REVIEW_SKILL`.

**Requires a `gh` account.** `_gh-account.sh` pins `GH_TOKEN` for the run so a concurrent
`gh auth switch` in another shell cannot flip identity mid-run. Set yours:

```bash
export WATCHDOG_GH_ACCOUNT=your-gh-login
```

## Cost

Five Opus lanes per PR. `--limit 1` is one PR per hour. Raise it only if you have looked at
what a run costs you.
