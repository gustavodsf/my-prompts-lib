---
description: Plan and execute proportionate QA for an approved task or authorized GitHub issue.
argument-hint: [task identifier or issue number]
---

# QA

Use the `sdlc-qa` skill.

Derive QA cases from the current plan and select the validation surface. API work uses `curl` or an equivalent HTTP client in a user-visible terminal. UI/E2E work uses a visible Chrome or Brave session and three iterations, including one blind run by the opposite agent when available. Do not replace either visual validation path with headless execution by default.

Keep QA artifacts local and sanitized. Do not access AWS in guided mode. Do not commit task-generated QA Markdown.
