# Handoff: 2026-10-27-ig-translate

- Phase: plan (written, not yet plan-checked)
- Next: plancheck-flow, then execute-flow
- Plan: docs/plans/2026-10-27-ig-translate.md
- Design: docs/plans/2026-10-27-ig-translate-design.md
- Sprint 1: Tasks 1-2 done. Task 2 found the org rejects browser CORS, so the API path is now a native messaging host (Tasks 10-11). Task 3 drives the user's logged-in Instagram via Claude in Chrome on the test thread /direct/t/17843292048580540/ (partner = user's own second account): never press Enter or Send
- Decision gates: Task 3 (composer write method), Task 14 Step 5 (long hard call through the native port), Task 14 Step 7 (content-script dynamic import). Any BLOCKED there means revisiting the design
- API key: ~/.config/anthropic/api-key, needs anthropic-workspace-id from ~/.config/anthropic/configs/default.json. Never print it
- Task 15 has __FILL__ markers filled by Task 3
- Repo is local only, never push
