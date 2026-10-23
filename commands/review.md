---
description: Run the final cross-agent review for the current approved task or authorized GitHub issue.
argument-hint: [task identifier or issue number]
---

# Review

Use the `sdlc-review` skill.

Review only after the approved implementation and validation are complete. Give each reviewer a brief with the feature objective, acceptance criteria, recorded base and feature commits, complete diff, relevant full-file context, owned files or flows, and claims to verify. Work implemented with Claude is reviewed in Codex; work implemented with Codex is reviewed in Claude. Run four independent reviewers scoped to the current feature diff, consolidate only material findings, and do not modify code during review.

Publish only a sanitized summary to an authorized GitHub issue. Post an inline pull-request comment only when explicitly authorized and only when it has a valid changed-line anchor. Keep detailed review Markdown local and out of commits.
