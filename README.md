# my-prompts-lib

A reusable SDLC skill library for Claude Code and Codex. Keep one clone as the source of truth, then link its skills and shared `sdlc/` rules, templates, and error catalog into both assistants. Every skill is invoked directly (`/sdlc-plan`, `/sdlc-review`, …); there are no separate command files.

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

The installer links `sdlc` and each skill individually (`~/.claude/skills/<name>`, `~/.codex/skills/<name>`), so skills it does not own — synced or personal ones — stay untouched. It does not manage `CLAUDE.md`, `AGENTS.md`, or command files; keep your own global instructions. With `--replace`, a regular pre-existing `sdlc` is renamed in place as `sdlc-old-<timestamp>`, and a pre-existing skill is moved to `skills-backup/<name>-old-<timestamp>` beside `skills/`, so the backup is not loaded as a duplicate skill. Existing symbolic links are refused, even with `--replace`. A `skills` directory that is itself a symbolic link from an older install is refused; remove that link and rerun.

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

`--track` copies `scripts/monitor.sh` to a private runner at `~/.local/share/apolo-sdlc/runners/<owner>/<repository>/monitor.sh` (mode `0700`), so later changes to this configuration clone never reach the schedule; re-run the same `--track` command to update the runner after reviewing the new monitor. The cron entry invokes only that runner with `--scheduled --repo <cloned-project>`, discards standard output, and overwrites `last-error.log` next to the runner on each run, so only the latest scheduled error is kept and the log cannot grow without bound. `--track` refuses to schedule when the runner, the tracked clone, or any of their parent directories can be modified by another user; shared sticky directories such as `/tmp` are accepted. Re-running the same command reuses the links and clone, and replaces only its own marked cron entry; unrelated entries are preserved. The clone is shallow (`--depth 1`) to minimize initial network and disk use; deepen it manually if interactive work needs history. It does not run Claude, use `curl` or AWS, push, comment on issues, or create pull requests.

`--track` is not yet available in `install.bat`; use `--local` on Windows and create a Task Scheduler action for `scripts\monitor.bat --repo C:\absolute\path\to\project` every 15 minutes. The scheduled user needs an authenticated `gh` CLI; Claude is not invoked by the schedule.

## Workflow guarantees

- Guided ClickUp/Jira work keeps the human at approval gates and never accesses AWS.
- GitHub tracking begins only after the persisted authorization and remains read-only when scheduled. Interactive work keeps task artifacts local and requires human approval before external writes.
- API validation uses visible terminal HTTP evidence. UI/E2E validation uses a visible browser and sanitized screenshots or console/network evidence.
- Claude work is reviewed in Codex and Codex work in Claude, with independent correctness, performance, security, and duplication review areas.

## Skills

| Skill | Use |
| --- | --- |
| [sdlc-project-context](skills/sdlc-project-context/SKILL.md) | Build local architecture, back-end, and front-end context before planning |
| [sdlc-plan](skills/sdlc-plan/SKILL.md) | Resolve the ClickUp/Jira ticket or authorized issue and write the local execution plan |
| [sdlc-qa](skills/sdlc-qa/SKILL.md) | Plan and run proportionate QA through visible terminal or browser paths |
| [sdlc-evidence](skills/sdlc-evidence/SKILL.md) | Capture and index sanitized API or UI/E2E evidence |
| [sdlc-review](skills/sdlc-review/SKILL.md) | The review standard (find → verify → sweep → classify, with a security checklist) plus the [feature review](skills/sdlc-review/feature-review.md): cross-agent, four areas, and bounded delta reviews after corrections |
| [sdlc-pr](skills/sdlc-pr/SKILL.md) | Open the pull request and address reviewer comments, with explicit approval for every external write |
| [sdlc-github-issue](skills/sdlc-github-issue/SKILL.md) | Read-only issue monitoring and the authorized `vamos trabalhar <issue>` lifecycle |
| [pr-watchdog](skills/pr-watchdog/SKILL.md) | Five-lane, read-only pull request review that runs the `sdlc-review` standard; see its [README](skills/pr-watchdog/README.md) |

Shared rules live in [sdlc/SDLC.md](sdlc/SDLC.md), the error catalog in [sdlc/error.md](sdlc/error.md), and local document templates in [sdlc/templates/](sdlc/templates/). Each skill links to them with a relative path, which resolves both inside this clone and through the installed links.

## License

See [LICENSE](LICENSE).
