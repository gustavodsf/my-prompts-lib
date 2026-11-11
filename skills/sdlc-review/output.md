# SDLC Review — reading cheaply and output format

Part of the review standard in [SKILL.md](SKILL.md). Read before writing the report.

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

The first line of every report (after optional YAML frontmatter, as in a PR Watchdog lane) must be exactly `VERDICT: PASS`, `VERDICT: CHANGES`, or `VERDICT: BLOCKED`. These replace the older labels `Approved`, `Changes Requested`,
and `Blocked` (`PASS` = Approved, `CHANGES` = Changes Requested, `BLOCKED` = Blocked).
Treat a first line that still uses an old label as the mapped value.

```markdown
VERDICT: PASS | CHANGES | BLOCKED

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

```

**Verdict rules** — `BLOCKED` = a spec violation, a Critical security finding in code this
diff introduces, or a must-run CI gate (Build, tests) skipped. `CHANGES` = any other
Critical. `PASS` = otherwise.

A capped premise-derived finding **cannot produce `BLOCKED`** on its own.
