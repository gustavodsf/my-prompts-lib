# PR Watchdog — cost model and backwards mode

Read only when tuning cost or running calibration (`corpus.sh`, `ground-truth.sh`).

## Cost model — for anyone tuning this

Cost is **context x turns**, not output. Every token in a lane's context is re-read on every
later turn, so a kilobyte loaded early is paid by every turn that follows.

Measured 2026-08-26 on one lane: peak context 143k (14% of the 1M window, no compaction),
55 turns, **5.36M tokens billed** for 37k of findings. Across a run: cache reads are ~95% of
throughput, output ~0.6%. Per-run totals ranged 6.4M to 60.6M.

So the levers, in order:

1. **Keep artifacts out of context** — grep for the lines that bear on a finding rather than
   reading whole files. An 80x reduction on `blame.txt`, multiplied by every remaining turn.
2. **Fewer, larger reads** of anything a lane will read fully. One read of `diff.patch` beats
   nine `sed` chunks by ~800k tokens; chunking trades a little carrying cost for a lot of
   turn cost.
3. **Bound turns.** Comparable lanes ran 39 and 113 turns for equivalent findings.
4. **Then** cap run frequency — which is what the window budget does.

Optimising output tokens is close to pointless at 0.6% of throughput.

## Backwards mode — calibration

`--calibrate N` reviews N already-merged PRs and scores the result against what actually
happened, instead of reporting to the user as if the PR were still open.

```bash
~/.claude/skills/pr-watchdog/scripts/corpus.sh <N>          # merged into test, newest first
~/.claude/skills/pr-watchdog/scripts/ground-truth.sh <pr> <merge-sha>
```

**Only merged PRs count.** A closed-unmerged PR was abandoned and a draft was never offered
for review — neither carries a decision worth learning from, and both would train the
reviewer on work nobody accepted. `corpus.sh` filters them out.

Run the normal five lanes against the merged PR's diff, blind — lanes must not see the
ground truth, or they are not reviewing, they are pattern-matching the answer. Then compare:

| Label | Strength | Meaning |
|---|---|---|
| `postMergeFixes` | **Strong** | Commits touching the same files after the merge with a fix/revert/hotfix subject. Something got through review and had to be repaired. |
| `humanFlagged` | Weak | What human reviewers said. A recall proxy only — humans miss things too, so silence here is not proof the code was clean. |

Score each PR into `<outDir>/calibration.md`:

- **Caught** — a confirmed finding that matches a human comment or a post-merge fix
- **Missed** — a post-merge fix or human comment with no matching finding at any vote level
- **Unsupported** — a confirmed finding nothing in the record corroborates. Not automatically
  a false positive: reviewers miss real bugs. Label it unsupported, not wrong.
- **Threshold check** — for each miss, say what vote level it *did* reach. A finding that
  landed at 3-of-5 and turned out real is evidence the threshold is too strict.

Then append to `calibration/` beside this skill, and only from repeated evidence:

- `blind-spots.md` — categories that produced Missed rows more than once. These get folded
  into the lane prompt as an explicit "look here" list.
- `false-positives.md` — Unsupported claims that recur with the same shape.
- `threshold.md` — the running tally of what 4-of-5, 3-of-5, and 2-of-5 each caught and missed.

**What this is and is not.** The model does not learn. This is evidence-driven prompt
tuning: the corpus tells you which sentence to add to `lane-prompt.md`, and the next
calibration run tells you whether it helped. Never edit `lane-prompt.md` off a single PR.

**The corpus is small.** In a 5-PR sample, human comments ran 0-5 per PR and post-merge
fixes were 0 across all five. The strong label is sparse, so a run of 20 PRs will not
support a threshold change. Say the sample size next to every rate you quote, and treat
anything under ~100 merged PRs as directional only.

ARGUMENTS: $ARGUMENTS
