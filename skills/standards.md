# Project Standards Reference

The single source of truth for git, commit, and PR conventions used by `/open-pr`.

## Branch Naming

- Format: `<JIRA-TICKET-ID>` (e.g., `PROJ-1234`)
- Base branch: `<base-branch>` (configure per project, e.g., `main`, `develop`, `master`)
- No forks — branch directly in the project repo

## Commit Message — Conventional Commits

Pattern: `<type>(<scope>): <description>`

### Types

- `feat` — New feature
- `fix` — Bug fix
- `docs` — Documentation changes
- `refactor` — Code refactoring
- `test` — Adding or updating tests
- `chore` — Maintenance tasks

### Scopes (based on where most changes live)

Scopes are project-specific and should map to top-level modules, apps, or libraries in your repo. Define them per project in your local conventions. Examples:

- `<app-name>` — `apps/<app-name>/`
- `<lib-name>` — `libs/<lib-name>/`
- `shared` — cross-cutting changes, tooling, configuration, or documentation

For changes that span multiple areas or affect general tooling/config/docs, use `shared` (or your project's equivalent).

### Examples

```
feat(api): add new account limits endpoint
fix(shared): correct calculation in remaining area usage
refactor(db): optimize query performance for large datasets
chore(shared): add documentation and tooling updates
```

## PR Title

```
<JIRA-TICKET-ID>: <type>(<scope>): <description>
```

Example: `PROJ-1234: fix(db): change setGlobalAnalysisLimit to INSERT instead of UPDATE`

## PR Body Template

```markdown
## Summary

<bullet points describing changes>

## Testing

<how the changes were tested>

## Related

- Jira: <JIRA-TICKET-ID>
```

## Workflow Rules

- **Single commit per PR** — squash before pushing
- **Rebase, don't merge** — `git fetch origin <base-branch> && git rebase origin/<base-branch>`
- **Format + lint must pass** before push:
  - `npx nx format:write --files="<changed-files>"`
  - `npx nx affected --target=lint`
- **Force-push** uses `--force-with-lease` only
- **Jira linking** is mandatory — every PR must reference a valid ticket
