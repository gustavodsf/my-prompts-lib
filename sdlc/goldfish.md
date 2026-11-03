# Goldfish check

Based on Google's Elephant-Goldfish Model (https://github.com/google/elephant-goldfish-model): the session that wrote the design (the Elephant) shares its blind spots, so a reviewer with **no context** checks whether the document stands on its own.

## Panel (parallel lenses)

One Goldfish misses what a differently focused one sees, so the check is a **panel**: independent context-free reviewers run in parallel, each with one lens, each reading only `design.md`, `INDEX.md` and `codemap.md`.

| Lens | Asks |
| --- | --- |
| comprehension | explain the plan back; symbols not in `codemap.md` |
| adversarial | edge cases, failure modes, how it breaks |
| security | secrets, permissions, AWS, personal data, privacy |
| testability | every AC has a concrete automated test; every task a file |
| simplicity | over-scope; a simpler option for the same ACs; planned duplication, a god class, or speculative abstraction ([anti-patterns](../skills/sdlc-review/anti-patterns.md)) |

- **Set:** `goldfish_lenses` in [agents.yml](agents.yml) (default: bug → comprehension, testability; feature → all five).
- **Diversity:** lenses alternate over `goldfish_agents` (default grok, then a fresh claude); unavailable agents drop out, and with none left a fresh `design`-agent process runs every lens ([fallback rule](SDLC.md#agents-per-phase)).
- **Each lens** answers `Verdict: Pass|Partial|Fail` plus at most 5 bullets. No readable verdict counts as Fail.
- **The Elephant consolidates:** any Fail blocks (fix `design.md`, rerun the panel once); every Partial becomes an edit to `design.md` or a one-line reason to keep it; Pass needs nothing. Lanes run it with `agent-run.sh goldfish-panel <prompt> <cwd> <metrics.md> <bug|feature>`, which prints each lens and `PANEL: PASS|PARTIAL|FAIL` and keeps no files.

## When

After `design.md` is drafted and before it is presented for approval (guided mode), posted as a plan comment (GitHub mode), or implemented.

## How

1. In a lane, use the panel above. Interactively, spawn one **fresh subagent** per lens, in parallel with no conversation history (Claude Code: `Agent`/Task; Codex: `spawn_agent`). A review in the same context is not a Goldfish check: if no subagent tool exists, say so and record the limitation.
2. Give it only these paths and the prompt below — no summary, no chat history:
   - `project-doc/_project/INDEX.md`
   - `project-doc/_project/codemap.md`
   - `project-doc/<task-id>/design.md` (or `<specDir>/design.md` in a lane)
   - read access to the repository checkout

Base prompt, verbatim (the panel appends the lens line):

> You have no prior context. Read INDEX.md, then design.md, then grep codemap.md as needed. Reply with: (1) the plan explained back in at most 10 lines; (2) every `path#symbol` in design.md that is not in codemap.md and is not marked `(new)`; (3) any acceptance criterion with no TDD task, and any task with no file; (4) a Pass/Partial/Fail grade per criterion below; (5) GO only if nothing is Fail, else NO-GO with the reasons. Do not write files.

Rubric (AIDOS-style, one grade each):

| Criterion | Pass | Partial | Fail |
| --- | --- | --- | --- |
| Problem | current vs desired behavior is testable | vague in places | missing or a solution in disguise |
| Options | ≥2 options with a reasoned choice | one option, trade-offs named | no trade-offs |
| AC → tests | every AC names a test | some unnamed | none |
| Symbols | all in `codemap.md` or `(new)` | 1–2 unknown | flow invents code |
| Scope | out-of-scope listed, ≤150 lines | one missing | unbounded |

3. The Elephant compares the explanation with its intent. A wrong explanation means the document is ambiguous: fix `design.md`, not the reviewer.
4. Fix every missing symbol and uncovered criterion, then rerun once if the verdict was NO-GO.

## Output

The Goldfish reply is **not saved as a file**. Only the resulting corrections land in `design.md`. Mention "Goldfish: PASS|PARTIAL", the lenses, agents and grades (or the limitation) in the plan presentation or comment.
