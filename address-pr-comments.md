# Address PR Comments

Address code review comments on a pull request systematically — categorize feedback, plan changes with user approval, implement, validate, then commit and push.

## How to Use

Reference this prompt in your AI assistant: "Address PR comments for PROJ-1234 #address-pr-comments".

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `JIRA_STORY` | — | Jira ticket ID (e.g., `PROJ-1234`). Inferred from branch name or PR title if not provided |
| `PR_NUMBER` | — | GitHub PR number. Inferred from current branch if not provided |
| `COMMIT_STRATEGY` | `single` | `single` (one commit), `individual` (one per logical group), or `ask` (confirm each) |
| `PREFERRED_REMOTE` | `origin` | Git remote to push to. Ask the user and remember the choice for the session if multiple remotes exist |

## Context

You are a senior software engineer addressing code review feedback on a PR. Your task is to systematically address each review comment while maintaining code quality and following the project's conventions (see `CLAUDE.md` or repository docs).

## Prerequisites Validation

Before starting, verify:
- [ ] Current directory is a git repository: `git status`
- [ ] GitHub CLI is authenticated: `gh auth status`
- [ ] Working on the correct branch with a pending PR
- [ ] Node.js and the project's package manager (`npm`, `pnpm`, or `yarn`) are available

## External Context (optional)

If MCP tools or other integrations are available, use them to enrich the review with external context:

- **Jira / issue tracker** — fetch ticket details, acceptance criteria, and linked documentation
- **Wiki / Confluence / Notion** — fetch any documentation linked from the ticket or PR
- **Chat (Slack / Teams / Discord)** — fetch related thread context if reviewers reference an off-PR conversation

If none of these are available, ask the user to paste the relevant context.

## Steps

### 1. Setup and Validation
**Objective**: Establish context and verify PR accessibility

#### A. Jira Story Analysis
- Delegate to the [jira-validator](skills/jira-validator/SKILL.md) skill to resolve `$JIRA_STORY`, validate the `<PROJECT>-<NUMBER>` format, verify accessibility, and capture the ticket summary, status, and assignee.
- Block on validation failures (no ticket resolvable, format invalid, ticket not accessible) before proceeding.
- From the validated ticket, extract key requirements, acceptance criteria, and any linked documentation needed to evaluate the review feedback.

#### B. PR Identification and Validation
- If `$PR_NUMBER` is not provided:
  - Find the PR for the current branch: `gh pr view --json number,title,url`
  - If multiple PRs or none found, ask the user to specify the PR number
- Validate the PR exists and is accessible: `gh pr view $PR_NUMBER`
- Confirm the PR title contains `$JIRA_STORY` or ask the user to verify the correct PR

#### C. Current Branch Verification
- **Remote Selection**: If `$PREFERRED_REMOTE` is not set:
  - List available remotes: `git remote -v`
  - If only `origin` exists, use it without asking
  - Otherwise ask: "Which remote should I push to? Available: [list remotes]. Default: origin"
  - Remember the user's choice for this session
- Ensure on the correct feature branch: `git branch --show-current`
- If not on the PR branch, ask the user: "Switch to PR branch? Current: [branch], PR branch: [pr_branch]"
- Sync with the remote if needed: `git pull $PREFERRED_REMOTE [branch_name]`

### 2. Review Comment Analysis
**Objective**: Systematically catalog and understand all review feedback

#### A. Fetch Review Comments
- Get structured review data: `gh pr view $PR_NUMBER --json reviews`
- Extract review comments with context (file, line, comment text)
- Get general PR comments: `gh pr view $PR_NUMBER --json comments`

#### B. Comment Categorization
Organize comments by:
- **Critical**: Security issues, bugs, breaking changes
- **Major**: Design improvements, performance issues, maintainability
- **Minor**: Style, naming, documentation
- **Questions**: Requests for clarification or explanation
- **Suggestions**: Optional improvements

#### C. Comment Context Gathering
For each comment:
- Identify affected file and line numbers
- Read surrounding code context
- If the comment references external docs/links, fetch additional context using available tools
- Note any conflicting feedback between reviewers

### 3. Implementation Planning
**Objective**: Create a systematic plan to address all feedback

#### A. Dependency Analysis
- Identify comments that depend on others (e.g., refactoring that affects multiple files)
- Group related changes that should be implemented together
- Flag potential conflicts between different reviewer suggestions

#### B. Implementation Sequence
- **Phase 1**: Critical security/bug fixes
- **Phase 2**: Major architectural/design changes
- **Phase 3**: Minor improvements and style fixes
- **Phase 4**: Documentation and clarification responses

#### C. Change Impact Assessment
For each planned change:
- Estimate complexity and time required
- Identify potential side effects
- Note testing requirements
- Plan a rollback strategy if needed

### 4. User Collaboration and Approval
**Objective**: Get user buy-in for the implementation approach

#### A. Present Comprehensive Plan
Show the user:
- Summary of all review comments by category
- Proposed implementation sequence
- Estimated effort and complexity
- Any conflicts or concerns identified

#### B. Individual Comment Review
For each comment (starting with Critical):
- **Show**: Original comment with file/line context
- **Propose**: Specific solution approach
- **Ask**: "Approve this approach? Alternative suggestions?"
- **Wait**: For explicit user approval before proceeding
- **Document**: User's decision (approve/modify/reject/defer)

#### C. Conflict Resolution
If reviewer feedback conflicts:
- Present both perspectives clearly
- Suggest a resolution approach
- Ask the user to choose a direction or request reviewer clarification
- Document the resolution for the PR response

### 5. Implementation Phase
**Objective**: Implement approved changes systematically

#### A. Setup Change Tracking
- Create a checklist of approved changes
- Track completion status as you work
- Note any implementation challenges encountered

#### B. Implement Changes by Priority
For each approved change:
- **Before**: Show the current code
- **Implement**: Make the change following project patterns
- **Validate**: Ensure the change compiles and basic functionality works
- **Test**: Run relevant tests if quick validation is possible
- **Mark Complete**: Update the tracking checklist

#### C. Handle Implementation Issues
If implementation problems arise:
- Document the specific issue
- Present alternative approaches
- Ask the user for guidance: continue, modify approach, or defer
- Update the implementation plan accordingly

### 6. Testing and Validation
**Objective**: Ensure all changes work correctly together

Use the project's own scripts — inspect `package.json` `scripts` (or the relevant `nx`/`turbo`/`pnpm` config) to find the right command. The examples below assume `npm`; substitute `pnpm` or `yarn` as appropriate.

#### A. Comprehensive Testing
- Run the full test suite: `npm test` (or `npm run test`, `npx nx affected --target=test`, etc.)
- If tests fail: **STOP** and present failure details to the user
- Run linting/style checks: `npm run lint` (or `npx nx affected --target=lint`)
- Fix any test failures iteratively

#### B. Integration Validation
- Build the project successfully: `npm run build` (or `npx nx affected --target=build`)
- Test key functionality affected by the changes
- Verify no regressions are introduced
- **Error Recovery**: If integration issues are found, present options to the user

#### C. Code Quality Review
- Self-review all changes for consistency
- Ensure changes follow existing patterns
- Verify documentation is updated if needed
- Check for any TODO comments or incomplete implementations

### 7. Response Preparation
**Objective**: Prepare a comprehensive response to reviewers

#### A. Change Summary Creation
- Document what was changed for each comment
- Note any alternative approaches taken
- Explain the rationale for design decisions
- Identify any suggestions not implemented and why

#### B. Reviewer Communication Strategy
- Prepare a response for each individual comment
- Address questions with clear explanations
- Thank reviewers for valuable feedback
- Request re-review of specific areas if needed

### 8. Commit and Push Strategy
**Objective**: Commit changes appropriately based on the strategy

All commit messages — and, if the PR title needs updating, the PR title — **must follow** the conventions defined in [skills/standards/SKILL.md](skills/standards/SKILL.md): Conventional Commits (`<type>(<scope>): <description>`), Jira-prefixed PR titles, and the workflow rules (single commit per PR when applicable, rebase over merge, format + lint gates).

#### A. Commit Strategy Execution
Based on `$COMMIT_STRATEGY`:

**Single Commit**:
- Stage all changes: `git add .`
- Create a comprehensive commit message: "Address code review feedback"
- Include bullet points of major changes addressed
- Commit: `git commit -m "[message]"`

**Individual Commits**:
- For each logical group of changes:
  - Stage related files: `git add [files]`
  - Create a specific commit message: "[specific change description]"
  - Commit: `git commit -m "[message]"`

**Ask Strategy**:
- Present commit options for each change group
- Let the user decide on commit granularity
- Execute the user's preferred approach

#### B. Pre-Push Validation
- Show staged changes: `git diff --cached`
- Confirm commit messages are descriptive
- Ask: "Push changes and notify reviewers?"
- **Final Check**: Verify all review comments have been addressed

### 9. Follow-up Actions
**Objective**: Complete the review response cycle

#### A. Push and Notify
- Push changes: `git push $PREFERRED_REMOTE [branch]`
- Verify the push was successful
- Comment on the PR with a summary of changes made
- Request re-review from the original reviewers

#### B. Documentation Update
- Update any tracking documents
- Note any follow-up actions needed
- Document lessons learned for future reviews

## Error Recovery Strategies

- **Issue tracker unavailable**: Continue with user-provided context if the MCP/integration fails
- **PR Access Issues**: Verify permissions and authentication
- **Git Conflicts**: Guide the user through the resolution process
- **Test Failures**: Present clear error details and suggested fixes
- **Build Issues**: Identify specific problems and provide solutions
- **Reviewer Conflicts**: Facilitate communication and decision-making

## Success Criteria

- [ ] All review comments systematically addressed or documented why not
- [ ] User approved each significant change before implementation
- [ ] All tests pass after changes
- [ ] Code follows project conventions and quality standards
- [ ] Clear commit history with descriptive messages
- [ ] Reviewers notified with a comprehensive response
- [ ] No regressions introduced by changes

## Best Practices

### Communication Guidelines
- Always explain the rationale for significant design decisions
- Be respectful and appreciative of reviewer feedback
- Ask for clarification rather than guessing reviewer intent
- Provide context for why alternative approaches were chosen

### Code Quality Maintenance
- Maintain consistency with existing codebase patterns
- Ensure changes don't introduce technical debt
- Update tests and documentation as needed
- Follow team coding standards and conventions
