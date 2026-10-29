# Handoff: 2026-10-28-ios-keyboard

- Phase: execute. Sprints 1-4 COMPLETE (Sprint 4 phone results and geometry in docs/ios-keyboard-notes.md,
  "Sprint 4: keyboard on the phone").
- Next: Sprint 5 Tasks 5.1-5.3 (Linux build) from docs/plans/2026-10-28-ios-keyboard.md, then Task 5.4 on the
  iPhone (USB + user checklist, 12 items). Each task: spec review, then quality review.
- Sprint 5 changed after Sprint 4 (user's call): the in-row emoji key is the protly key (`setKeyboardType(.emojis)`
  runs `act(nil)`), and the bar has no icon, only Apple's three slots. The user keeps only Protly + Emoji installed,
  so iOS's bottom-left key opens Emoji.
- Sprint 6 carry-overs: space drag stalls between characters and has no vertical move; 걍 (rid) and 걔 (ro) commit
  as English.
- Env: `. ~/.local/share/swiftly/env.sh` before swift/xtool. Secrets.swift via ios-app/scripts/make-secrets.sh; never print it.
- In this shell `grep` is ugrep: use `command grep` or `grep -F` for patterns with `$`.
