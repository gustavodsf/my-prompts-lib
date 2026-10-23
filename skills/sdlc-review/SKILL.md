---
name: sdlc-review
description: Review a diff to the DeliverThat engineering standard — find candidates, verify each one, sweep for gaps, classify. Every finding carries a named failure scenario, a file:line, and a CONFIRMED/PLAUSIBLE verify label. Use when reviewing a branch or PR before opening it, checking your own changes, running the SDLC final or follow-up feature review, or asking "would the watchdog flag this". Also the standard the PR Watchdog's five lanes run. Triggers on "review this", "review my branch", "check my changes", "watchdog review", "would this pass review", "final review".
argument-hint: "[task identifier or issue number]"
version: 1.1.0
---

# SDLC Review

**SDLC feature review:** when this skill is invoked to review an approved feature or a correction cycle, follow [feature-review.md](feature-review.md) beside this file. It orchestrates the reviewers; each reviewer applies the standard below. A pr-watchdog lane ignores this paragraph.

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
- **Premise caps and evidence rules** — from Brendan Glancy's analysis of PR 3019, where all
  five lanes blocked a legitimate PR on one shared unverifiable assumption.

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
| **Acceptance criteria** | Ticket ID from the branch name (`TECH-6053/...` → `TECH-6053`). Fetch it: `ToolSearch` for `+clickup get_task`, then `clickup_get_task` with `include: ["description","checklists","subtasks"]` — use `markdown_description`, and note ACs sit in the description as `- [ ]`, not in `checklists`. No ticket ID → say so and score spec compliance `Unverified`. | `ticket.md`, already fetched |
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

## Phase 1 — Find candidates

**Surface every candidate you can name a failure scenario for.** Let Phase 2 kill the wrong
ones. A half-believed candidate dropped silently here never reaches verify — that is the
dominant cause of misses, and it is worse than a candidate that gets refuted.

1. **Spec compliance** — per acceptance criterion in `ticket.md`: implemented? matches?
   behaviour in the diff that no criterion asked for (scope creep)? → AC table.
2. **Correctness** — edge cases (null/empty/boundaries/overflow), async correctness (no
   floating promises), explicit error handling (no silent failures), type safety (no `any`,
   no unjustified assertions), state transitions match the spec.
3. **Removed-behaviour audit** — for every line the diff **deletes or replaces**, name the
   invariant it enforced, then find where the new code re-establishes it. Cannot find it →
   candidate: a dropped guard or early return, a narrowed validation, a removed `catch`, a
   lost regex anchor, a deleted assertion that covered a real case. **Read the `-` lines
   directly; never infer what was removed from what was added.**
4. **History check** — for hunks that delete or rewrite pre-existing lines, find the
   introducing commit in `blame.txt` and read its message. If those lines came from a fix
   (says fix/bug/hotfix/revert, or names a ticket), verify the new code still handles that
   scenario. **Silently reverting an old fix is a top regression source and invisible to a
   diff-only read.** Bounded: only replaced or deleted hunks.
5. **Cross-file trace** — for every symbol the diff changes that others consume (exported
   function, service method, DTO field, Prisma field, event payload, route contract), grep
   its call sites and check each against the change: new precondition, changed return shape
   or nullability, new thrown error, changed ordering, renamed field still read elsewhere.
   **A broken call site outside the diff is a finding** — the diff broke it. Cite the call
   site's line, not the changed line.
6. **Comment contracts** — read comments in and around every changed region as local rules:
   "keep in sync with X", "do not reorder", "must run before Y", "gateway handles auth — no
   app guard", `@deprecated`, a warning above a constant. A change contradicting a comment is
   a candidate; a change that makes a nearby comment false without updating it is a Warning.
   Check any `CLAUDE.md` in the touched directories — nested ones carry the most specific
   rules.
7. **Architecture & layering** — against `checklist/`: no data access outside repositories,
   dependency direction inward, no Hydrated/Prisma types past the repository/mapper seam,
   DTOs validated at boundaries, no cross-module imports.
8. **Grain** — for any filter, `WHERE` clause, eligibility check, or financial calculation:
   is it evaluated at the right grain — Delivery vs Job vs Driver vs Pool period? A rule
   filtering on a parent-level column when the decision belongs at the child level is a real
   bug in this codebase, not a style note.
9. **Security** — for whichever OWASP category the diff actually touches (new route → `A01`,
   raw SQL → `A03`, a money or quantity limit → `A04`, a webhook → `A08`, outbound HTTP from
   input → `A10`, an LLM prompt → `LLM01`), check its probe in `security-checklist.md`.
   Stay light — flag what the diff puts in front of you. **An exploitation path, or it is not
   a finding.**
10. **Database & migrations** — backward-compatible and compliant with `rule-migrations.md`.
    On high-volume tables, unbatched DML, non-`CONCURRENTLY` index builds, or table-rewriting
    `ALTER`s are **Critical**. Also: no N+1, transactions for multi-write, indexes for new
    query patterns. **Never edit an applied migration** — the checksum changes and
    `migrate deploy` fails on any stage that already ran it.
11. **Silent bails** — any early return, `continue`, sentinel string, no-op stub, or swallowed
    `catch` that leaves no log and no trace in the data.
12. **Test quality** — tests assert behaviour not implementation; assertions exact enough to
    catch a regression; no test that would still pass if the feature were disabled; mocks
    minimal and realistic; a test that re-derives its expectation by running the production
    mapping proves nothing. You cannot measure coverage — say so rather than estimating.
13. **Prior-PR feedback** — query `prior-prs.json` for review comments on these files. A
    reviewer correction the diff repeats is a candidate; cite the PR and quote the comment.
14. **Docs** — if the diff changes a module's public behaviour, contract, or conventions, its
    `CLAUDE.md` or `docs/` should be updated in the same change. Warning if missing.

Steps 3–6, 13 and 14 read outside the diff by design. That widens what you **read**, never
what you **report**: a finding still has to trace back to a line this diff changed, or to a
call site this diff broke. **Pre-existing defects the diff merely sits next to are not
findings.**

---

## Phase 2 — Verify

**Never skip it. An unverified candidate is not a finding.**

1. **Dedup** — candidates on the same line *and* the same mechanism collapse into one; keep
   the most concrete failure scenario. Same line, different mechanisms → keep both.
2. **Label each remaining candidate exactly one of:**

| Label | Means |
|---|---|
| **CONFIRMED** | You can name the inputs or state that trigger it and the resulting wrong output, crash, or violated AC. Quote the line. |
| **PLAUSIBLE** | The mechanism is real, the trigger is uncertain (timing, environment, config, flag state). State what would confirm it. |
| **REFUTED** | Factually wrong, provably impossible (show the type, constant or invariant), already handled elsewhere in this diff (cite the guard), or pure style with no observable effect. Quote the line that proves it. |

3. **Keep CONFIRMED and PLAUSIBLE. Drop REFUTED** — not as a Suggestion, not as a caveat.

### Calibration — PLAUSIBLE by default

Do **not** refute a candidate for being "speculative" when the state is realistic: a race on
a shared row, a concurrent Lambda invocation, `null` on a rare-but-reachable path (error
handler, cold cache, absent optional field, a `?? undefined` mapper), falsy-zero treated as
missing, off-by-one on a boundary the code does not exclude, retry storms and partial
failures, an unbounded read that is small in dev and large in prod.

**Refute only what you can construct from the code, and quote it.**

### A convention finding must quote its rule

If the mechanism is "the conventions say so", verification means opening that source and
quoting the sentence that calls this issue out **specifically**. A rule you remember but
cannot quote, or one that only gestures at the theme, is **REFUTED as a convention finding**.
It may still survive on its own merits as a correctness candidate.

### Framework mitigations are legitimate refutations

Prisma parameterizes ordinary queries. A `ValidationPipe` already validates the DTO. A guard
already present covers the route. **A private API's auth is handled by the gateway
authorizer, not the app** — never flag a missing app-level guard on a `DTRestApiV2({private:
true})` route. So is a lint rule or the typechecker already catching it: CI runs those.

### Unverifiable premises — cap, do not refute

Some candidates rest on something you cannot check: a value present in an environment, a job
that actually runs, a table that holds rows, a flag set in a stage.

- **Name it** in the finding as `**Unverified premise**: …`
- **Give the exact command** that would settle it, e.g.
  `aws ssm get-parameters-by-path --path /cicd`
- **Cap the severity at Warning.** Certainty about an inference is not evidence about the
  world.

**A regression claim needs prior behaviour cited** — the merge-base file, the removed hunk
lines, or the deleted spec. Without it, report what you *can* verify ("this path is
untested", "this value is not provided anywhere in the repo") rather than "this change breaks
X". PR 3019 was blocked by five lanes making the same unverifiable regression claim.

---

## Phase 3 — Sweep for gaps

One more pass over the diff and the enclosing functions, as a fresh reviewer holding the
verified list. Hunt **only** for defects not already on it. Aim at what Phase 1 reliably
misses:

- moved or extracted code that dropped a guard, a `try`/`catch`, an `await`, or a regex
  anchor on the way;
- setup/teardown asymmetry in tests — a mock restored on one path but not another, a seeded
  row never cleaned up, shared state leaking between cases;
- config, env, or feature-flag defaults flipped — a `?? true` that used to be `?? false`, a
  LaunchDarkly fallback, a changed DTO default;
- a Prisma `select`/`include` narrowed so a downstream consumer now reads `undefined`, or a
  mapper that stopped populating a field;
- copy-paste between two new call sites where only one got the fix.

New candidates re-enter Phase 2 before they can be reported. Nothing new → one line saying
so. Never pad.

---

## Phase 4 — Classify

**Critical** (security, spec violation, data loss, wrong money, missing error handling,
unsafe migration) · **Warning** (real defect or a rule this repo enforces) ·
**Suggestion** (a change a senior engineer would actually ask for).

**There is no Nitpick severity.** Prettier runs on commit and ESLint runs in CI — style is
already decided and enforced, so hunting it spends the review's budget on an answer the repo
already has.

**Severity is impact. The verify label is confidence. They are independent axes.**

- A **PLAUSIBLE Critical still blocks** — the label tells the developer the trigger is
  uncertain, and one extra fix cycle is cheaper than shipping it.
- Never inflate severity because a candidate is uncertain.
- Never demote a CONFIRMED Critical to keep a PR green.
- **Correctness outranks cleanup.** If the report runs long, cut Suggestions — never a
  Critical or a Warning.

### Not findings — cut before writing

- Pre-existing issues the diff did not introduce; real issues on lines it did not touch.
- **Anything the toolchain already decides.** Do not merely refrain from reporting these —
  **do not spend turns looking for them.** Verified in this repo:

  | Tool | Already enforces |
  |---|---|
  | **Prettier** (pre-commit) | Quotes, semicolons, trailing commas, indentation, line width, bracket and arrow spacing — **all formatting** |
  | **ESLint** `tseslint recommended` | Unused variables, undefined references, unsafe type constructs |
  | **ESLint** `@typescript-eslint/no-floating-promises` (error) | **Un-awaited promises. Do not audit for these.** |
  | **ESLint** `import/no-cycle` (error) | Import cycles |
  | **tsc** | Type errors |
  | **CI + prep exclusions** | Generated output, lockfiles, build artifacts — never in your diff |

  A finding matching any row is not a finding, and looking for it is not worth the turns.
  Report a *failed* check from `checks.txt`; never re-derive its job.
- Style, naming and formatting preferences of any kind.
- General quality complaints — thin coverage, vague docs, unspecific security worries —
  unless a rule in `checklist/` requires it.
- Issues explicitly silenced in the code, e.g. behind a lint-ignore comment.
- Changes obviously intentional and part of the broader change.

---

## Reading cheaply — measured, not a preference

**Every token in your context is re-read on every later turn.** Cost is context × turns.
Measured: 143k peak context, 55 turns, 5.36M tokens billed for 37k of findings.

- **Grep the big artifacts.** `grep -A3 -F 'path/file.ts' blame.txt` is ~200 tokens; the file
  is up to 16k. Query `prior-prs.json` with `jq`. Find a checklist section with
  `grep -n '^#'` then `sed` just that section.
- **But read `diff.patch` in ONE pass.** You will need all of it. Walking it in `sed` chunks
  cost a measured lane nine turns and ~800k tokens more than a single read. Turns are the
  multiplier.
- **Past ~35 tool calls and still gathering?** Go to the write-up with what you have and say
  what you did not reach.

## Output

Bullets and tables. No prose paragraphs, no hedging. State the defect and the fix.

```markdown
## Spec compliance
| AC | Status | Evidence (file:line) |

## Issues
Verify: <n> candidates → <c> confirmed, <p> plausible, <r> refuted. Sweep: <k> new | none.
Format: **ID — Title** · `path/file.ts:N` · CONFIRMED | PLAUSIBLE · one sentence.
A PLAUSIBLE line names what would confirm it, in that same sentence.
A capped line carries **Unverified premise**: … and the command that settles it.

### Critical
### Warning
### Suggestion
(Omit any empty severity.)

## Test review
CI: <pass/fail/skipped per gate from checks.txt>. Tests, lint and typecheck not run locally.
Coverage not measurable.

## Not covered
Areas the diff touches that this review did not reach. `None` if none.

VERDICT: Approved | Changes Requested | Blocked
```

**Verdict rules** — Blocked = a spec violation, a Critical security finding in code this diff
introduces, or a must-run CI gate (Build, tests) skipped. Changes Requested = any other
Critical. Approved = otherwise.

A capped premise-derived finding **cannot produce Blocked** on its own.
