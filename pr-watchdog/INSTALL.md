# Installing pr-watchdog

Two separate things. The skill is portable; the hourly routine is not.

## 1. The skills — copy them

Two skills, one archive:

```bash
tar xzf pr-watchdog.tar.gz -C ~/.claude/skills/
```

- **`pr-watchdog`** — the orchestrator: scan, gates, lanes, reconcile, metrics.
- **`watchdog-review`** — the review standard. Invocable on its own with
  `/watchdog-review`, and the same file the watchdog's five lanes run.

**Run `/watchdog-review` on your own branch before you open a PR.** Same rules the watchdog
will apply, so nothing in its summary should surprise you — and if a rule misfires on your
work, fix the rule. That file is the tuning mechanism; it improves by being used.

Every path in `scripts/` resolves from `$HOME`, so no editing is needed if your repo sits
at `~/dev/Delivery-API`. Otherwise export overrides in your shell profile:

```bash
export WATCHDOG_REPO="$HOME/code/Delivery-API"
export WATCHDOG_WS="$HOME/code/.pr-watchdog"
```

Requires `gh` (authenticated), `jq`, and `git`. Nothing else — no `npm install`.

Check it:

```bash
~/.claude/skills/pr-watchdog/scripts/scan.sh | jq length
```

That prints how many open PRs are pending review. It writes nothing.

## 2. The routine — you have to create your own

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

`watchdog-review/SKILL.md` is the single review standard — four phases, all checks, verify labels,
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
