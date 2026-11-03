# AGENTS.md — single source of truth for agents working on this repository

Every agent (Claude, Codex, Grok, Gemini, others) follows this file. Agent-specific files (`CLAUDE.md`, `GEMINI.md`) only point here; never add rules to them.

## What this repo is

A library of SDLC skills, shared rules, templates, and lane prompts installed into `~/.claude` and `~/.codex` by `scripts/install.sh`. Start at [README.md](README.md); shared rules are in [sdlc/SDLC.md](sdlc/SDLC.md).

## Rules for changing it

- Keep it small: SKILL.md ≤150 lines, details in sibling files; follow the size limits in `sdlc/templates/`.
- Never break skill frontmatter (`name`, `description`, `argument-hint`).
- Agent assignments live only in [sdlc/agents.yml](sdlc/agents.yml). An agent never reviews its own output.
- The installer never manages a user's global `CLAUDE.md`, `AGENTS.md`, or unrelated skills.
- Do not invent CLIs: an agent without a configured command is unavailable.

## Before committing

```bash
for t in tests/*.sh; do bash "$t" || exit 1; done   # includes evals/run.sh static checks
```

When a skill, template, `SDLC.md`, or lane prompt changes, also run the agent evals (`EVAL_AGENT='claude -p' evals/run.sh --agent`) when an agent is available, and report the result in the PR.

Write commits, code, and docs in English; Conventional Commits.
