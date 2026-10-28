# Handoff: 2026-10-27-ig-translate

- Phase: plan (written, not yet plan-checked)
- Next: plancheck-flow, then execute-flow
- Plan: docs/plans/2026-10-27-ig-translate.md
- Design: docs/plans/2026-10-27-ig-translate-design.md
- Sprint 1 is spikes. Task 2 needs ANTHROPIC_API_KEY exported by the user. Task 3 drives the user's logged-in Instagram via Claude in Chrome: never press Enter or Send, user picks the thread
- Decision gates: Task 2 (format + thinking, browser origin), Task 3 (composer write method), Task 12 Step 4 (content-script dynamic import). Any BLOCKED there means revisiting the design
- Task 13 has __FILL__ markers filled by Task 3
- Repo is local only, never push
