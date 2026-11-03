# Goldfish check

Based on Google's Elephant-Goldfish Model (https://github.com/google/elephant-goldfish-model): the session that wrote the design (the Elephant) shares its blind spots, so a reviewer with **no context** checks whether the document stands on its own.

## When

After `design.md` is drafted and before it is presented for approval (guided mode), posted as a plan comment (GitHub mode), or implemented.

## How

1. Use the `goldfish` agent from [agents.yml](agents.yml) (never the `design` agent). Spawn a **fresh subagent** with no conversation history (Claude Code: `Agent`/Task; Codex: `spawn_agent`). A review in the same context is not a Goldfish check: if no subagent tool exists, say so and record the limitation.
2. Give it only these paths and the prompt below — no summary, no chat history:
   - `project-doc/_project/INDEX.md`
   - `project-doc/_project/codemap.md`
   - `project-doc/<task-id>/design.md` (or `<specDir>/design.md` in a lane)
   - read access to the repository checkout

Prompt, verbatim:

> You have no prior context. Read INDEX.md, then design.md, then grep codemap.md as needed. Reply with: (1) the plan explained back in at most 10 lines; (2) every `path#symbol` in design.md that is not in codemap.md and is not marked `(new)`; (3) any acceptance criterion with no TDD task, and any task with no file; (4) GO or NO-GO with the blocking reasons. Do not write files.

3. The Elephant compares the explanation with its intent. A wrong explanation means the document is ambiguous: fix `design.md`, not the reviewer.
4. Fix every missing symbol and uncovered criterion, then rerun once if the verdict was NO-GO.

## Output

The Goldfish reply is **not saved as a file**. Only the resulting corrections land in `design.md`. Mention "Goldfish: GO" (or the limitation) in the plan presentation or comment.
