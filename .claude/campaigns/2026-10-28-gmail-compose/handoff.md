# Handoff: 2026-10-28-gmail-compose

- Phase: plan (written, self-reviewed; plan code applied to a scratch copy: npm test 86/86, gmail tests 11/11, eval-email 0 lang failures)
- Next: execute Sprint 2 (Tasks 2-3), then Sprint 3 (Tasks 4-8)
- Plan: docs/plans/2026-10-28-gmail-compose.md
- Design: docs/plans/2026-10-28-gmail-compose-design.md
- Spike facts: docs/spike-notes-gmail.md
- Scope: Gmail compose/reply translation only. Instagram files are not touched
- Open [UNVERIFIED], all checked in Task 8: Gmail autosave/Send pick up the direct DOM replace; content-script import() under Gmail CSP; Alt+T free in Gmail; signature markup on an account with a signature; note placement before the compose toolbar table
- Safety: Claude never types into a Gmail compose and never clicks Send; the user sends to their own address in Task 8
- API key: ~/.config/anthropic/api-key plus workspace_id; never print it. Repo is local only, never push
