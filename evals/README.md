# Prompt evals

Run whenever a skill, template, `SDLC.md`, `agents.yml`, or a lane prompt changes.

```bash
evals/run.sh                 # static checks only (fast, no agent)
EVAL_AGENT='claude -p' evals/run.sh --agent   # also run each reference task through an agent
```

**Static checks** (always): skill frontmatter (`name`, `description`), size limits (SKILL.md ≤150 lines, templates within their stated limits), relative links resolve, `agents.yml` obeys the no-self-review rule, every lane skill references `lane-mode.md` exactly once.

**Agent evals** (`--agent`): each file in `tasks/` has a prompt and a `Pass if` checklist. The script sends the prompt (with this library's path) to `$EVAL_AGENT`, saves the answer in `evals/out/<task>.md` (git-ignored), and greps it for the required markers. Read the failures; a regression means fix the skill, not the eval. Record the result in the PR description.

Keep tasks few and small. Add one when a real failure happens (same spirit as `sdlc/error.md`).
