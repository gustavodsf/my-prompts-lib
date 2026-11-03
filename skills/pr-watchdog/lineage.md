# PR Watchdog — lineage

History only; not needed to run the watchdog.


**The review standard is the `sdlc-review` skill beside this one.** One file, team-owned, and the
only place review behaviour is defined. `prep.sh` copies it into each bundle so a run always
reviews against the version current when it started.

It replaced the vendored `dt-review` tree and the repo-snapshot overrides. There are no
longer overrides layered on someone else's skill — the standard is written for the watchdog,
so the lane prompt carries identity and isolation only.

Consolidated 2026-08-27 from: Monorepo `flow-review` 2.4.0 (four-phase find/verify/sweep/
classify, 3-state verify labels, PLAUSIBLE-by-default, removed-behaviour audit, cross-file
trace), Anthropic's `code-review` plugin (history, prior-PR and comment-contract finders),
a team analysis of a falsely blocked PR (premise caps), and the Delivery-API strict/legacy severity
table.
