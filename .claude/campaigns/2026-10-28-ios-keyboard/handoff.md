# Handoff: 2026-10-28-ios-keyboard

- Phase: execute. Sprints 1-2 COMPLETE (gate PASS, notes "Sprint 2: KeyboardKit").
- Sprints 3-5 planned in full and reviewed (APPROVE_WITH_CHANGES, all 19 items applied 2026-10-29) in
  docs/plans/2026-10-28-ios-keyboard.md, section "Sprints 3-6 (re-planned 2026-10-28 after the Sprint 2 gate)".
  All Swift in it was compiled in scratch (ProtlyCore 46 tests; xtool builds of the Sprint 4 and 5 stages, 0
  warnings). Sprint 6 is a contract until Sprint 5's phone check.
- Sprint 3 COMPLETE (40 tests). Next: Sprint 4 Tasks 4.1-4.3 (Linux build), then Task 4.4 on the iPhone (USB + user checklist). Each task: spec review, then quality review.
- Open [UNVERIFIED]: `noticeFieldMoved` relies on `hasText` while only marked text is in the field; Task 4.4
  item 1/12/16 decide, the plan says which clause to drop if item 1 splits words.
- The user judges the design changes (bar-tap flip, clipboard chip, haptics off) by using them in Sprints 4-5.
- Env: `. ~/.local/share/swiftly/env.sh` before swift/xtool. Secrets.swift via ios-app/scripts/make-secrets.sh; never print it.
- The user keeps Apple's Korean keyboard installed until the Sprint 4 checklist passes.
