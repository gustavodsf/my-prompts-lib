# PR Watchdog — local mode

Read when invoked with `--local`. Rules in [SKILL.md](SKILL.md) still apply.

## Local mode — five lanes on your working tree, before any PR

`/pr-watchdog --local` reviews **uncommitted work**, with the same five lanes, the same
standard and the same agreement percentages as a PR review. Use it to get the watchdog's
verdict before you open the PR, not after.

```bash
~/.claude/skills/pr-watchdog/scripts/prep-local.sh [base]
```

Then Steps 3–5 exactly as for a PR: fetch the ticket, spawn five lanes from
`lane-prompt.md`, reconcile on Fable. The bundle shape is identical, so nothing downstream
changes.

### What differs, and why

| | PR mode | Local mode |
|---|---|---|
| Scan and the four gates | `scan.sh` | **Skipped.** The user asked for this run; there is no queue to pace. |
| Scope | `pull/<n>/head` | A snapshot commit of your working tree |
| CI | `checks.txt` from `gh pr checks` | `no PR yet - CI has not run on this code` |
| `finish.sh` | Stamps the SHA into `state.json` | **Do not run it.** There is no PR number to record. |
| Output | `reviews/PR-<n>/<sha>/` | `reviews/LOCAL-<branch>/<sha>/` |

**Two rules that must not misfire:**

- **`ciAvailable: false` in `meta.json` means CI has not run, which is NOT the same as a
  required gate skipping.** Never return `Blocked — no CI evidence` in local mode. Report CI
  as "not run — no PR yet" and let the findings decide the verdict.
- **The window budget does not apply.** A local run is a deliberate request, not a sweep. Say
  the cost in the report — a five-lane review is 6–60M tokens — so the choice is informed.

### The snapshot, and why it is built the way it is

`prep-local.sh` writes a commit object through a **temporary index**, then builds a worktree
at it. Working tree, index and stash list are all untouched.

Two reasons it is not simpler:

- **Lanes must review the same bytes.** Reading the live tree while you keep typing means
  five lanes review five different states, and the agreement percentage stops meaning
  anything.
- **`git stash create` is not sufficient — it excludes untracked files.** Measured on
  a real 50-file feature: 11 changed paths were untracked, and they held the entire new
  module. A snapshot without them reviews the change with its subject
  missing and would plausibly report the implementation as absent. The temporary index runs
  `git add -A`, so untracked files are in and `.gitignore` still keeps `node_modules` out.

`meta.json` reports `dirtyPaths` and `untrackedPathsIncluded` — state both in your report so
the reader knows what was covered.
