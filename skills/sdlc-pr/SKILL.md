---
name: sdlc-pr
description: Open the pull request for a completed and reviewed task or authorized GitHub issue, and later address reviewer comments on it. Use when the user asks to open, update, or respond to a pull request.
argument-hint: "[open | feedback] [task identifier, issue number, or PR number]"
---

# Pull request

Follow [../../sdlc/SDLC.md](../../sdlc/SDLC.md) and check [../../sdlc/error.md](../../sdlc/error.md). Push, create, or comment on a pull request only when the user explicitly asks in the current task. Never force-push, rebase, amend, or squash without an explicit request.

## Open

Preconditions: all approved tasks are committed, required checks pass, and the `sdlc-review` record has an approved disposition for every finding. Verify `gh auth status`, the feature branch, and the base branch recorded for the task.

- **Title:** `<ticket-or-issue>: <type>(<scope>): <description>`, matching the repository's Conventional Commits types and scopes when it uses them.
- **Body:**

  ```markdown
  ## Summary
  - <what changed and why>

  ## Testing
  - <checks run, evidence summary, manual QA status>

  ## Related
  - <ClickUp/Jira task URL or GitHub issue #number>
  ```

Run `gh pr create --base <base-branch>` with that title and body, then report the PR URL. Never include secrets, personal data, internal endpoints, or raw AWS data. For an authorized GitHub issue, link the pull request in the issue.

## Feedback

1. Resolve the PR from the argument or the current branch with `gh pr view --json number,title,url`. Confirm it references the task or issue.
2. Fetch review threads and comments with `gh pr view <number> --json reviews,comments` and `gh api repos/{owner}/{repo}/pulls/<number>/comments`. Read the surrounding code for each comment.
3. Classify each comment as **Critical** (security, bug, breaking change), **Major** (design, performance, maintainability), **Minor** (style, naming, docs), **Question**, or **Suggestion**. Flag conflicting reviewer requests.
4. Present the plan with one proposed response per comment and wait for the user's decision on each: implement, alternative, decline with reason, or defer.
5. Implement approved changes as normal SDLC tasks: failing test when meaningful, focused verification, commit approval. Run `sdlc-review` in delta mode on the correction diff.
6. Draft concise replies: what changed, or why a suggestion was declined. Post replies, push, and request re-review only after explicit approval.

If the issue tracker or GitHub is unavailable, continue with user-provided context and record the limitation.
