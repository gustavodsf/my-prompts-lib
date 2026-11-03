# SDLC Review — callers and lineage


**This file is the review standard.** Two callers run it:

- **You, on your own branch** — `/sdlc-review` before you open a PR. Same rules the
  watchdog will apply, so nothing in its summary should surprise you.
- **The PR Watchdog** — five independent lanes each run this file against the same diff, and
  a reconciler measures how many of them agreed.

Improve review quality by improving this file. There is nowhere else to change it, and both
callers pick the change up immediately.

**Running it yourself is the point.** The team finds this file's weaknesses by getting a bad
finding on their own work, not by reading it. If a rule here misfires on your branch, fix the
rule.

Lineage, so you know what you are editing:
- **Four-phase pipeline, 3-state verify, sweep, PLAUSIBLE-by-default** — from Monorepo
  `flow-review` 2.4.0, which the Monorepo team flagged as an enhancement that should travel
  back to Delivery-API.
- **History / prior-PR / comment-contract finders** — from Anthropic's `code-review` plugin
  (Boris Cherny), which `flow-review` and this file adopted independently.
- **Premise caps and evidence rules** — from a team analysis of a PR where all
  five lanes blocked a legitimate PR on one shared unverifiable assumption.
