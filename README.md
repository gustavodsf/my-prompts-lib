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

On Windows, run the equivalent command in Command Prompt or PowerShell (see [Windows](#windows) for everything else):

```bat
scripts\install.bat --local --dry-run --replace
scripts\install.bat --local --replace
```

The installer links `sdlc` and each skill individually (`~/.claude/skills/<name>`, `~/.codex/skills/<name>`), so skills it does not own — synced or personal ones — stay untouched. It does not manage `CLAUDE.md`, `AGENTS.md`, or command files; keep your own global instructions. With `--replace`, a regular pre-existing `sdlc` is renamed in place as `sdlc-old-<timestamp>`, and a pre-existing skill is moved to `skills-backup/<name>-old-<timestamp>` beside `skills/`, so the backup is not loaded as a duplicate skill. Re-running the installer is always safe: it first uninstalls the previous install — links in `sdlc` and `skills/` that point into any clone of this library (or dangle after that clone moved), including skills that no longer exist — and then links again, with no `--replace` needed for them. `--replace` is only for real files or directories at a managed target. Symbolic links that point elsewhere are yours and are refused. `--uninstall` removes only the managed links (`./scripts/install.sh --uninstall`, `scripts\install.bat --uninstall`); with `--track URL` it also removes that project's runner directory and its marked cron entries, keeping the clone and other projects' entries. `--dry-run` previews both. A `skills` directory that is itself a symbolic link from an older install is refused; remove that link and rerun.

On Windows, directories are linked with a symbolic link when allowed (Developer Mode or an elevated prompt), otherwise with a junction, which needs no privilege. Do not delete the managed clone while its links are active.

## Authorized GitHub monitor

The monitor reads open GitHub issues and pull requests when no issue is authorized. An explicit authorization is bound to the repository root and `origin` remote, but the read-only monitor (`monitor.sh`) never starts Claude, writes to GitHub, pushes, or creates a pull request. Unattended work is a separate opt-in; see [Autonomous lanes](#autonomous-lanes).

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

The authorization state is local: `~/.local/state/apolo-sdlc/` on macOS/Linux and `%LOCALAPPDATA%\apolo-sdlc\state\<hash>.state` on Windows (the older `monitor.bat` used `%LOCALAPPDATA%\apolo-sdlc\authorized-issue`; authorize the issue again after upgrading). It is bound to the repository and remote. A closed issue is marked completed; an open authorized issue remains ready for interactive execution.

Use an explicit interactive session for code changes, HTTP evidence, GitHub comments, pushes, and pull requests. The read-only monitor has no Claude executor, wrapper, AWS access, `curl`, or GitHub-write path.

## GitHub tracking setup

On macOS or Linux, `--track` combines local assistant configuration with a single tracked GitHub project. It validates an HTTPS GitHub repository URL, clones the project under `~/.local/share/apolo-sdlc/projects/`, and creates or updates one marked 15-minute cron entry. Preview it before making changes:

```bash
./scripts/install.sh --track https://github.com/pastor-ia/app --dry-run --replace
./scripts/install.sh --track https://github.com/pastor-ia/app --replace
```

`--track` copies `scripts/monitor.sh` to a private runner at `~/.local/share/apolo-sdlc/runners/<owner>/<repository>/monitor.sh` (mode `0700`), so later changes to this configuration clone never reach the schedule; re-run the same `--track` command to update the runner after reviewing the new monitor. The cron entry invokes only that runner with `--scheduled --repo <cloned-project>`, discards standard output, and overwrites `last-error.log` next to the runner on each run, so only the latest scheduled error is kept and the log cannot grow without bound. `--track` refuses to schedule when the runner, the tracked clone, or any of their parent directories can be modified by another user; shared sticky directories such as `/tmp` are accepted. Re-running the same command reuses the links and clone, and replaces only its own marked cron entry; unrelated entries are preserved. The clone is shallow (`--depth 1`) to minimize initial network and disk use; deepen it manually if interactive work needs history. Without `--lanes`, it does not run Claude, use `curl` or AWS, push, comment on issues, or create pull requests.

On Windows, `scripts\install.bat --track URL` does the same with Task Scheduler instead of cron (see [Windows](#windows)). The scheduled user needs an authenticated `gh` CLI; Claude is not invoked by the monitor.

## Autonomous lanes

On macOS or Linux, `--track` can also schedule two autonomous lanes that run Claude unattended with `claude -p` and permission prompts off. They write to GitHub with your `gh` account, so enable them only for a repository you own and review the prompts first:

```bash
./scripts/install.sh --track https://github.com/pastor-ia/app --lanes issue,ci --checkout /absolute/path/to/project/app --dry-run --replace
./scripts/install.sh --track https://github.com/pastor-ia/app --lanes issue,ci --checkout /absolute/path/to/project/app --replace
```

- **issue lane** (every 15 minutes): takes one open issue written by the owner and advances it one stage per run. It posts the plan from `sdlc-plan` and waits for an `aprovado` comment, implements with TDD and posts progress, reviews with `sdlc-review` (Codex as the opposite agent) and waits for `aprovado: 1, 3` / `all` / `none`, applies the selected fixes, runs `sdlc-qa`, publishes sanitized `sdlc-evidence` with screenshots on the orphan `qa-evidence` branch, and opens the pull request with `sdlc-pr`. Merging stays with you.
- **ci lane** (7 minutes later): handles owner comments on open pull requests through `sdlc-pr` feedback, fixes broken pull request pipelines, and diagnoses failed release or deploy runs with a fix pull request or an issue. It never triggers releases or deploys.

Options:

- `--lanes issue`, `--lanes ci` or `--lanes issue,ci` choose the lanes. `--checkout` is required: an existing checkout of the tracked repository, owned by you and not writable by other users. The lanes never change its branch or files; they work in `worktrees/` beside it and keep task documents in `docs/spec-XXXX/` beside it, out of commits.
- `--owner` is the only GitHub login whose issues and comments the lanes obey; it defaults to the login reported by `gh`. Comments from anyone else, bots and CI logs are treated as data.
- To post as a separate bot account, save its token as `state/bot-token` in the runner directory, owned by you with mode `0600`. The runner passes it to Claude as `GH_TOKEN`, so the token never appears in prompts, commands or logs; a token file with looser permissions stops the lanes.

What gets installed in the private runner directory (`~/.local/share/apolo-sdlc/runners/<owner>/<repository>/`): copies of `scripts/lane.sh` and of `lanes/issue.md`, `lanes/ci.md` and `lanes/deny.json`, plus `project.conf`, `state/` and `logs/`. Like the monitor runner, these copies change only when you re-run `--track`. Each run appends Claude's output to `logs/issue.log` or `logs/ci.log` and overwrites `logs/<lane>-last-error.log` with runner errors; the monitor keeps its own `last-error.log`. The two lanes share one lock, so a run skips silently while the other lane or a previous run is still working.

`lanes/deny.json` blocks deploys, AWS writes, merges (including through `gh api`), ref rewrites, workflow runs and re-runs, force pushes, pushes to `main` or `master`, `crontab`, `git reset --hard`, `sudo`, and edits to Claude's settings, even with permission prompts off. At install time the runner's copy also denies edits to the lane's own runner, prompts, deny rules and `project.conf`. These rules match command text, so a determined workaround (another branch name, a script) can slip past them: before enabling the lanes, turn on **branch protection** for the repository's default branch on GitHub (no direct pushes, pull requests required, no bypass for the account the lanes use). That is the guarantee the lanes rely on. Cron starts with a minimal `PATH`, so the installer records the real directories of `claude`, `gh`, `git`, `codex` and `node` in each lane entry; re-run `--track` after moving them or switching Node versions. Set `CHECKPOINT_LINES=<n>` when running `--track --lanes` to write `checkpoint_lines=<n>` to `project.conf` (auto-mode checkpoint size; default comes from `sdlc/agents.yml`).

The skills learn the unattended behavior from [sdlc/lane-mode.md](sdlc/lane-mode.md), which applies only when `lane.sh` set `APOLO_SDLC_LANE` and the prompt is a lane prompt. Guided ClickUp/Jira work and the interactive `vamos trabalhar` flow never use it, and nothing under `lanes/` is linked into `~/.claude` or `~/.codex`.

To disable the lanes, re-run the same `--track` command without `--lanes`: their cron entries are removed and the read-only monitor stays.

## Windows

Everything runs natively on Windows (no WSL): `scripts\install.ps1`, `monitor.ps1`, `lane.ps1`, `agent-run.ps1` and `resolve-agents.ps1` are PowerShell ports of the `.sh` scripts, with the same options, rules and guardrails, and work on Windows PowerShell 5.1 and PowerShell 7. `install.bat` and `monitor.bat` only forward their arguments (to `pwsh` when installed, else `powershell`). The `.sh` scripts stay the macOS/Linux version; both are tested on every push (`ci/windows.yml`, to be moved to `.github/workflows/`).

```bat
scripts\install.bat --local
scripts\install.bat --track https://github.com/OWNER/REPO
scripts\install.bat --track https://github.com/OWNER/REPO --lanes issue,ci --checkout "C:\Users\me\src\my project"
scripts\install.bat --track https://github.com/OWNER/REPO --uninstall
```

- **Scheduling.** Task Scheduler tasks in the `\apolo-sdlc\` folder replace cron: `apolo-sdlc-track-OWNER-REPO` every 15 minutes, `apolo-sdlc-lane-issue-OWNER-REPO` at :00/:15/:30/:45 and `apolo-sdlc-lane-ci-OWNER-REPO` at :07/:22/:37/:52. Each task's description is its marker (`apolo-sdlc-track:OWNER/REPO`, `apolo-sdlc-lane:issue:OWNER/REPO`), so a re-run replaces exactly that project's tasks and `--uninstall` removes only them. Tasks run as you, only while you are logged on (no stored password); a PowerShell window may flash briefly. If registering fails, the previous tasks and runner files are restored.
- **Data.** Clones, runners and logs live in `%LOCALAPPDATA%\apolo-sdlc\` (`projects\`, `runners\OWNER\REPO\`, `runners\OWNER\REPO\logs\`; errors of the last run in `logs\<lane>-last-error.log`). `APOLO_SDLC_DATA` and `APOLO_SDLC_TASK_FOLDER` override them.
- **Tools.** `claude`, `codex`, `grok`, `gh` and `git` are resolved to absolute paths at install time (`.exe` or the npm `.cmd` shim) and written to `project.conf`, together with a `path=` line, because scheduled tasks do not get your interactive PATH. Re-run the installer after moving a tool. Claude Code on Windows needs Git for Windows (Git Bash).
- **Links.** Symbolic links first, then junctions for directories (no Developer Mode needed); `APOLO_SDLC_NO_SYMLINK=1` forces junctions. Uninstall deletes only the link, never the target.
- **Guardrails.** Identical to the shell version: agents started by `agent-run.ps1` get no `GH_TOKEN`/`GITHUB_TOKEN`/`GH_ENTERPRISE_TOKEN`, no credential prompts and an unusable push URL; only the lane's own Claude session gets the bot token and pushes. `state\bot-token` must be readable only by you, SYSTEM and Administrators (checked from its ACL). The POSIX owner/permission checks of the runner directories are not ported; keep `%LOCALAPPDATA%` private (the default).
- **Code map.** In Windows PowerShell 5.1, `>` writes UTF-16; use `node codemap.mjs <repo> --out project-doc\_project\codemap.md`.
- **Line endings.** `.gitattributes` keeps `*.sh` LF and `*.ps1`/`*.bat`/`*.cmd` CRLF in every checkout.
- **Tests.** `pwsh -File tests\windows\run.ps1` (add `-Real` to also register and remove real tasks in `\apolo-sdlc-ci\`); the suites mock the Task Scheduler cmdlets and use fake `claude`/`codex`/`grok`/`gh` binaries.

## Workflow guarantees

- Guided ClickUp/Jira work keeps the human at approval gates and never accesses AWS.
- GitHub tracking begins only after the persisted authorization and remains read-only when scheduled, unless you opt into autonomous lanes; their only approvals are the owner's `aprovado` comments on the issue. Interactive work keeps task artifacts local and requires human approval before external writes.
- API validation uses visible terminal HTTP evidence. UI/E2E validation uses a visible browser and sanitized screenshots or console/network evidence.
- Claude work is reviewed in Codex and Codex work in Claude, with independent correctness, performance, security, and duplication review areas.

## Documentation model (Elephant / Goldfish)

Inspired by Google's [Elephant-Goldfish Model](https://github.com/google/elephant-goldfish-model):

| Layer | Where | Lifetime | Limit |
| --- | --- | --- | --- |
| Elephant (durable) | `project-doc/_project/INDEX.md`, `architecture.md`, `business-rules.md`, `decisions.md` | project | 30 / 80 lines, one line per rule, ≤5 lines per ADR |
| Code map (generated) | `project-doc/_project/codemap.md` | regenerated | never hand-written |
| Task | `project-doc/<task>/design.md`, `evidence.md` | one task, then archived or deleted | 150 lines |
| Goldfish | fresh subagent | one check, nothing saved | — |

See [sdlc/SDLC.md](sdlc/SDLC.md) and [sdlc/goldfish.md](sdlc/goldfish.md). Agents per phase: [sdlc/agents.yml](sdlc/agents.yml). Lanes resolve it with `scripts/resolve-agents.sh` (one fallback rule) and run each non-design agent through `scripts/agent-run.sh` (no approvals inside its sandbox, no token, no push); the installer records `codex_bin`, `grok_bin` and `gemini_bin` when found (override with `CODEX_BIN`, `GROK_BIN`, `GEMINI_BIN`). Prompt evals: [evals/](evals/README.md). Agent instructions for this repo: [AGENTS.md](AGENTS.md).

## Skills

| Skill | Use |
| --- | --- |
| [sdlc-project-context](skills/sdlc-project-context/SKILL.md) | Build the durable per-project context in `project-doc/_project/` (INDEX, one-page architecture, business rules, decisions) and the generated `codemap.md` |
| [sdlc-plan](skills/sdlc-plan/SKILL.md) | Resolve the ticket or authorized issue, write a ≤150-line `design.md`, and run the Goldfish check |
| [sdlc-intake](skills/sdlc-intake/SKILL.md) | Bug or feature, then at most 5 questions per round before the design (lane: `intake` comment gate) |
| [sdlc-implement](skills/sdlc-implement/SKILL.md) | Acceptance tests from `design.md` first (red), then code until all pass |
| [sdlc-qa](skills/sdlc-qa/SKILL.md) | Plan and run proportionate QA through visible terminal or browser paths |
| [sdlc-evidence](skills/sdlc-evidence/SKILL.md) | Capture and index sanitized API or UI/E2E evidence |
| [sdlc-review](skills/sdlc-review/SKILL.md) | The review standard (find → verify → sweep → classify, with a security checklist) plus the [feature review](skills/sdlc-review/feature-review.md): cross-agent, four areas, and bounded delta reviews after corrections |
| [sdlc-pr](skills/sdlc-pr/SKILL.md) | Open the pull request and address reviewer comments, with explicit approval for every external write |
| [sdlc-github-issue](skills/sdlc-github-issue/SKILL.md) | Read-only issue monitoring and the authorized `vamos trabalhar <issue>` lifecycle |
| [pr-watchdog](skills/pr-watchdog/SKILL.md) | Five-lane, read-only pull request review that runs the `sdlc-review` standard; see its [README](skills/pr-watchdog/README.md) |

Shared rules live in [sdlc/SDLC.md](sdlc/SDLC.md), the error catalog in [sdlc/error.md](sdlc/error.md), and local document templates in [sdlc/templates/](sdlc/templates/). Each skill links to them with a relative path, which resolves both inside this clone and through the installed links.

## License

See [LICENSE](LICENSE).
