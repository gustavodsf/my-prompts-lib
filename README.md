# my-prompts-lib

A reusable library of prompts and skills for AI coding assistants (Claude Code, Copilot Chat, etc.). Project-agnostic by default — drop it into any repo and configure your base branch and Jira project per use.

## Contents

| Entry | Type | Purpose |
| --- | --- | --- |
| [open-pr.md](open-pr.md) | Prompt / slash command | Orchestrates pull request creation with parallel validation and review |
| [skills/](skills/) | Skills | Specialized sub-agents invoked by the orchestrator |

## Layout

Each skill lives in its own folder with a `SKILL.md` file (YAML frontmatter + body), following the standard skill layout used by Claude Code:

```
skills/
├── code-reviewer/
│   └── SKILL.md
├── git-branch-validator/
│   └── SKILL.md
├── jira-validator/
│   └── SKILL.md
├── pr-creator/
│   └── SKILL.md
├── pr-manifest/
│   └── SKILL.md
└── standards/
    └── SKILL.md
```

`SKILL.md` frontmatter format:

```markdown
---
name: <skill-name>
description: <when to use this skill — used by the assistant to decide relevance>
---

# Skill body...
```

## Skills

| Skill | What it does |
| --- | --- |
| [standards](skills/standards/SKILL.md) | Single source of truth for branch, commit, and PR conventions |
| [pr-manifest](skills/pr-manifest/SKILL.md) | Manages the `PR-MANIFEST.md` scratchpad shared across sub-agents |
| [git-branch-validator](skills/git-branch-validator/SKILL.md) | Validates branch name, formats/lints, rebases against the base branch, enforces single-commit policy, and pushes |
| [jira-validator](skills/jira-validator/SKILL.md) | Resolves and validates the Jira ticket, captures summary/status/assignee |
| [code-reviewer](skills/code-reviewer/SKILL.md) | Thorough review of the branch diff with delta-mode support |
| [pr-creator](skills/pr-creator/SKILL.md) | Generates PR title/body and runs `gh pr create` against the configured base branch |

## Using `/open-pr`

Trigger from your AI coding assistant:

```
Open a PR for PROJ-1234 #open-pr
```

Available options:

- `/open-pr` — full guided workflow
- `/open-pr -jira=PROJ-1234` — specify the Jira ticket directly (skip branch extraction)
- `/open-pr --skipCodeReview` — skip code review (docs/trivial changes only)
- `/open-pr --skipBranchValidation` — skip git validation (branch already pushed and synced)

See [open-pr.md](open-pr.md) for the full execution flow and the standards it enforces.

## Configuring for your project

The library uses placeholders so it can be reused across repos. Set these per project (in your assistant's project instructions or by replacing the placeholders in a fork):

| Placeholder | Replace with |
| --- | --- |
| `<base-branch>` | Your repo's base branch (e.g., `main`, `develop`, `master`) |
| `<JIRA-TICKET-ID>` | Your Jira ticket pattern (e.g., `PROJ-1234`, `ABC-5678`) |
| Scopes in [standards](skills/standards/SKILL.md) | Your top-level apps/libs (e.g., `api`, `web`, `db`) |

## License

See [LICENSE](LICENSE).
