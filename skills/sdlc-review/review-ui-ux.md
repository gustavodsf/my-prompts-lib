# UI and UX review lenses

Run as the `review_ui_ux` agent from `sdlc/agents.yml` (default Codex). This is a documented exception to the no-self-audit rule: the same CLI as `implement` is allowed, but only in a fresh read-only session with no implementer context. You never edit production code. You write only:

- `project-doc/<task-or-issue-id>/round-<N>/review-ui.md`
- `project-doc/<task-or-issue-id>/round-<N>/review-ux.md`

(or `<specDir>/round-<N>/` in a lane). Each file follows [output.md](output.md) and starts with `VERDICT: PASS | CHANGES | BLOCKED` on line 1. Treat older `Approved` / `Changes Requested` / `Blocked` as `PASS` / `CHANGES` / `BLOCKED`.

If the branch has no user-visible or visual change, write `PASS` on both files and say so. Do not start the app.

## Look at it

If the change shows up on a page, look at it. Use the same visible Chrome or Brave path as [sdlc-qa](../sdlc-qa/SKILL.md), not agent-browser. Exercise the changed screens at desktop and a phone width. Capture screenshots into the task evidence folder when they support a finding or a pass. In lane mode there is no visible browser: run headless, record "headless lane run" as a limitation, and never claim a visible run (`sdlc/lane-mode.md`). If a needed port is already in use, never kill that process: record the limitation and skip the live look.

## UX (`review-ux.md`)

Flows a person can finish, loading / empty / error states, obvious copy, keyboard and focus, contrast, and whether the mobile width stays usable.

## UI (`review-ui.md`)

Design-system tokens and components (reuse, do not invent), spacing and typography consistency, contrast, overflow or clipping, and alignment with `_project/architecture.md` when it describes the front end.

`PASS` if there is no material visual or interaction issue. `CHANGES` for fixable issues. `BLOCKED` only when the UI is unusable or the look cannot be verified and the change required it.
