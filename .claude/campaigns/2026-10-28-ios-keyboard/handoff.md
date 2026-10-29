# Handoff: 2026-10-28-ios-keyboard

- Phase: execute, Sprint 2 of 6. Sprint 1 COMPLETE (ProtlyCore, 22 tests; eval + Sprint 3 carry-overs in
  docs/ios-keyboard-notes.md).
- Sprint 2: Task 2.2 done and reviewed (1683208, fixes f9c3327). Task 2.3: app installed on the iPhone
  (`cd ios-app && xtool dev run`, signing fine). Waiting on the user's 9-item checklist (plan lines 1287-1303).
- Next: record checklist results under "Sprint 2: bare spike" in docs/ios-keyboard-notes.md, commit
  `docs: Sprint 2 bare keyboard findings`; then Task 2.4 (KeyboardKit 9.9.1 vendored, color/image patch), Task 2.5 gate.
- After the gate: re-run plan-flow for Sprints 3-6 with docs/ios-keyboard-notes.md (includes Sprint 1 review carry-overs).
- Env: `. ~/.local/share/swiftly/env.sh` before swift/xtool. Secrets.swift via ios-app/scripts/make-secrets.sh; never print it.
