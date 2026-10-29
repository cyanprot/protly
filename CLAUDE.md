# protly

Write in Korean or English, send in English: a Chrome extension (Instagram, Gmail) and a custom iPhone keyboard
that types Korean and English on one QWERTY grid and offers Translate / Polish / Read clipboard from its bar.

## Plans of record

- iPhone keyboard features: `docs/plans/2026-10-28-ios-keyboard.md` (Sprints 1-5 done; Sprint 6 next).
- Keyboard visual verification (cloud): `docs/plans/2026-10-29-keyboard-visual.md`.
- Security review and test hardening (cloud): `docs/plans/2026-10-29-security-review.md`.
- Phone and simulator findings: `docs/ios-keyboard-notes.md`.
- English style for Translate and Polish: `docs/style-guide.md` (derived from `cyanprot/humanizer`). Code copies its
  prompt blocks verbatim and this file wins over the Sprint 7a draft.

## Layout

- Chrome extension: `src/`, `tests/`, `manifest.json`, build `scripts/build.mjs`. Native host: `host/`.
- iPhone: `ios-app/` (xtool app: container `Protly`, extension `ProtlyKeyboard`), logic in the Swift package
  `ios-app/ProtlyCore`, KeyboardKit 9.9.1 vendored at `ios-app/Vendor/KeyboardKit` (every change from upstream
  is in `protly.patch` and listed in `VENDORED.md`; keep both in sync).

## Rules

- English for code, comments, commits and docs.
- Never commit, print or log secrets. `ios-app/Sources/ProtlyKeyboard/Secrets.swift` is gitignored and written by
  `ios-app/scripts/make-secrets.sh`; CI and cloud sessions use a stand-in with an empty key.
- Tests run offline: `npm test` (extension, host) and `swift test --package-path ios-app/ProtlyCore` (needs a
  Swift toolchain). Both pass before every commit.
- The phone build (`xtool dev build` on the laptop) must keep working: do not edit `ios-app/Package.swift` or
  `ios-app/xtool.yml` without the tower.
- `.claude/agents/` and `.claude/hooks/` are vendored from magnusprot by its `scripts/vendor-cloud.sh` (commit in
  `.claude/magnusprot.lock`). Do not edit them here. `.claude/settings.json` wires the hooks for cloud sessions
  only (`CLAUDE_CODE_REMOTE=true`). `.claude/campaigns/` is local tower state and is gitignored.
