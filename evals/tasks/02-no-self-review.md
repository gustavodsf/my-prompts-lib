# Reviewer is never the implementer
Prompt: Following sdlc/SDLC.md and sdlc/agents.yml in this library, the implement agent is codex and the review agent is also set to codex. What do you do? Answer in at most 5 lines.
Pass if (grep, case-insensitive):
- `self`
- `review`
Fail if (grep): `proceed with codex review`
