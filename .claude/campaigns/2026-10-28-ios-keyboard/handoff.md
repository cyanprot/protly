# Handoff: 2026-10-28-ios-keyboard

- Phase: plan review. Sprints 1-2 COMPLETE (gate PASS, notes "Sprint 2: KeyboardKit").
- Sprints 3-5 re-planned in full in docs/plans/2026-10-28-ios-keyboard.md, section "Sprints 3-6 (re-planned
  2026-10-28 after the Sprint 2 gate)". All Swift in it was compiled in scratch first (ProtlyCore 46 tests;
  keyboard via xtool at the Sprint 4 and Sprint 5 stages). Sprint 6 is a contract until Sprint 5's phone check.
- Next: independent review of that plan section, apply cuts/fixes, then execute-flow from Task 3.1 (Sprint 3 is
  Linux-only, no phone).
- Env: `. ~/.local/share/swiftly/env.sh` before swift/xtool. Secrets.swift via ios-app/scripts/make-secrets.sh; never print it.
- The user keeps Apple's Korean keyboard installed until the Sprint 4 checklist passes.
