# my-prompts-lib

A reusable SDLC configuration library for Claude Code and Codex. Keep one clone as the source of truth, then link its rules, commands, skills, templates, and error catalog into both assistants.

## Safe installation

Keep this clone available after installation: the assistants use symbolic links, so updates pulled into the clone are immediately available without copying configuration files.

Preview the changes first. This command never changes configuration:

```bash
./scripts/install.sh --local --dry-run --replace
```

To install on macOS or Linux, explicitly authorize backup and replacement of existing managed targets:

```bash
./scripts/install.sh --local --replace
```

On Windows, run the equivalent command in Command Prompt:

```bat
scripts\install.bat --local --dry-run --replace
scripts\install.bat --local --replace
```

The installer links `CLAUDE.md` for Claude, `AGENTS.md` for Codex, and `sdlc`, `commands`, and `skills` for both. A regular pre-existing managed target is renamed in place as `<name>-old-<timestamp>` only when `--replace` is present. Existing symbolic links are refused, even with `--replace`.

Windows symbolic links require Developer Mode or an elevated Command Prompt. Do not delete the managed clone while its links are active.

## Authorized GitHub monitor

The monitor reads open GitHub issues and pull requests when no issue is authorized. An explicit authorization is bound to the repository root and `origin` remote, but scheduled runs remain read-only: they never start Claude, write to GitHub, push, or create a pull request.

After a human has said `vamos trabalhar <issue-number>`, persist that authorization from the clone:

```bash
./scripts/monitor.sh --repo /absolute/path/to/project --authorize 123
./scripts/monitor.sh --repo /absolute/path/to/project --dry-run
./scripts/monitor.sh --repo /absolute/path/to/project
```

The Windows equivalent is:

```bat
scripts\monitor.bat --repo C:\absolute\path\to\project --authorize 123
scripts\monitor.bat --repo C:\absolute\path\to\project --dry-run
scripts\monitor.bat --repo C:\absolute\path\to\project
```

Only one issue may be authorized at a time. Clear it before authorizing another issue:

```bash
./scripts/monitor.sh --clear-authorization
```

The authorization state is local: `~/.local/state/apolo-sdlc/` on macOS/Linux and `%LOCALAPPDATA%\apolo-sdlc\authorized-issue` on Windows. It is bound to the repository and remote. A closed issue is marked completed; an open authorized issue remains ready for interactive execution.

Use an explicit interactive session for code changes, HTTP evidence, GitHub comments, pushes, and pull requests. The scheduled monitor has no Claude executor, wrapper, AWS access, `curl`, or GitHub-write path.

## GitHub tracking setup

On macOS or Linux, `--track` combines local assistant configuration with a single tracked GitHub project. It validates an HTTPS GitHub repository URL, clones the project under `~/.local/share/apolo-sdlc/projects/`, and creates or updates one marked 15-minute cron entry. Preview it before making changes:

```bash
./scripts/install.sh --track https://github.com/pastor-ia/app --dry-run --replace
./scripts/install.sh --track https://github.com/pastor-ia/app --replace
```

The cron entry invokes only `monitor.sh --repo <cloned-project>` and writes a local log. Re-running the same command reuses the links and clone, and replaces only its own marked cron entry; unrelated entries are preserved. It does not run Claude, use `curl` or AWS, push, comment on issues, or create pull requests.

`--track` is not yet available in `install.bat`; use `--local` on Windows and create a Task Scheduler action for `scripts\monitor.bat --repo C:\absolute\path\to\project` every 15 minutes. The scheduled user needs an authenticated `gh` CLI; Claude is not invoked by the schedule.

## Workflow guarantees

- Guided ClickUp/Jira work keeps the human at approval gates and never accesses AWS.
- GitHub tracking begins only after the persisted authorization and remains read-only when scheduled. Interactive work keeps task artifacts local and requires human approval before external writes.
- API validation uses visible terminal HTTP evidence. UI/E2E validation uses a visible browser and sanitized screenshots or console/network evidence.
- Claude work is reviewed in Codex and Codex work in Claude, with independent correctness, performance, security, and duplication review areas.

## Contents

| Entry | Type | Purpose |
| --- | --- | --- |
| [open-pr.md](open-pr.md) | Prompt / slash command | Orchestrates pull request creation with parallel validation and review |
| [address-pr-comments.md](address-pr-comments.md) | Prompt / slash command | Systematically addresses code review comments on an existing PR |
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

## Using `/address-pr-comments`

Trigger from your AI coding assistant once a PR has review feedback:

```
Address PR comments for PROJ-1234 #address-pr-comments
```

Variables you can pass:

- `JIRA_STORY` — Jira ticket ID (inferred from branch/PR title if omitted)
- `PR_NUMBER` — GitHub PR number (inferred from current branch if omitted)
- `COMMIT_STRATEGY` — `single` (default), `individual`, or `ask`
- `PREFERRED_REMOTE` — defaults to `origin`

See [address-pr-comments.md](address-pr-comments.md) for the full workflow.

## Configuring for your project

The library uses placeholders so it can be reused across repos. Set these per project (in your assistant's project instructions or by replacing the placeholders in a fork):

| Placeholder | Replace with |
| --- | --- |
| `<base-branch>` | Your repo's base branch (e.g., `main`, `develop`, `master`) |
| `<JIRA-TICKET-ID>` | Your Jira ticket pattern (e.g., `PROJ-1234`, `ABC-5678`) |
| Scopes in [standards](skills/standards/SKILL.md) | Your top-level apps/libs (e.g., `api`, `web`, `db`) |

## License

See [LICENSE](LICENSE).
