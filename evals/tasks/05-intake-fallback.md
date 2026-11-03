# Intake asks little; agents fall back without self-review
Prompt: Using sdlc-intake and sdlc/SDLC.md from this library: (a) list the intake questions for the GitHub issue "Checkout total is wrong when a coupon is applied" given that the code and rules are readable; (b) with agents.yml implement=codex, review=codex, and only claude and codex installed, say which agent reviews and who breaks ties.
Pass if (grep):
- `bug`
- `claude`
- `human`
Max lines: 40
