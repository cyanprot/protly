# protly

Write in Korean or English, send in English: a Chrome extension (Instagram, Gmail) and a custom iPhone keyboard
that types Korean and English on one QWERTY grid and offers Translate / Polish / Read clipboard from its bar.

## Plans of record

- iPhone keyboard features: `docs/plans/2026-10-28-ios-keyboard.md` (Sprints 1-8 done).
- Simulator phone checks (cloud): `docs/plans/2026-10-30-sim-phone-checks.md` (replaces the USER steps of Tasks
  6.8, 7.7 and 8.5).
- Keyboard visual verification (cloud): `docs/plans/2026-10-29-keyboard-visual.md`.
- Security review and test hardening (cloud): `docs/plans/2026-10-29-security-review.md`.
- Typing fixes (cloud): `docs/plans/2026-10-30-typing-fixes.md` (plain-text composition, Spanish flip, space
  trackpad, simulator proof; research in `docs/research/`).
- Phone and simulator findings: `docs/ios-keyboard-notes.md`.

## Layout

- Chrome extension: `src/`, `tests/`, `manifest.json`, build `scripts/build.mjs`. Native host: `host/`.
- iPhone: `ios-app/` (xtool app: container `Protly`, extension `ProtlyKeyboard`), logic in the Swift package
  `ios-app/ProtlyCore`, KeyboardKit 9.9.1 vendored at `ios-app/Vendor/KeyboardKit` (every change from upstream
  is in `protly.patch` and listed in `VENDORED.md`; keep both in sync).

## Rules

- English for code, comments, commits and docs.
- Never commit, print or log secrets. `ios-app/Sources/ProtlyKeyboard/Secrets.swift` is gitignored and written by
  `ios-app/scripts/make-secrets.sh`; cloud sessions use a stand-in with an empty key. From Sprint 002 of
  the sim-phone-checks plan, the keyboard-shots workflow writes Secrets.swift from the Actions secret
  `PROTLY_API_KEY` (a CI-only key) through make-secrets.sh when it is set (empty stand-in otherwise), never prints
  it, and publish-shots.sh refuses any file containing `sk-ant-`.
- Tests run offline: `npm test` (extension, host) and `swift test --package-path ios-app/ProtlyCore` (needs a
  Swift toolchain). Both pass before every commit.
- The phone build (`xtool dev build` on the laptop) must keep working: do not edit `ios-app/Package.swift` or
  `ios-app/xtool.yml` without the tower.
- `.claude/agents/` and `.claude/hooks/` are vendored from magnusprot by its `scripts/vendor-cloud.sh` (commit in
  `.claude/magnusprot.lock`). Do not edit them here. `.claude/settings.json` wires the hooks for cloud sessions
  only (`CLAUDE_CODE_REMOTE=true`). `.claude/campaigns/` is local tower state and is gitignored.
