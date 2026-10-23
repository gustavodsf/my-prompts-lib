---
description: Run the final cross-agent review for the current approved task or authorized GitHub issue.
argument-hint: [task identifier or issue number]
---

# Review

Use the `sdlc-review` skill.

Review only after the approved implementation and validation are complete. Work implemented with Claude is reviewed in Codex; work implemented with Codex is reviewed in Claude. Run four independent reviewers scoped to the current feature diff, consolidate only material findings, and do not modify code during review.

Publish only a sanitized summary to an authorized GitHub issue. Keep detailed review Markdown local and out of commits.
