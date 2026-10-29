# Keyboard Visual Verification Implementation Plan

> **For Claude:** cloud campaign. Planes implement one sprint each from a pasted brief; the tower verifies and lands.

**Goal:** A GitHub Actions macOS job that installs the protly keyboard in an iOS Simulator, screenshots it in the
states that broke on the phone, measures the screenshots against Apple's own keyboard in the same simulator, and
the layout fixes that make every measurement pass.

**Architecture:** A CI-only Xcode project (XcodeGen) builds a tiny host app with one text field that embeds the
ProtlyKeyboard extension from the same sources the phone build uses. An XCUITest drives the simulator through
fixed scenarios and saves PNGs. A measuring script reads the PNGs and prints PASS/FAIL per check. The workflow
pushes the PNGs and the measurement report to an orphan branch `ci-shots`, so a cloud session can fetch and look
at them with git alone. The plane fixes the keyboard code, re-runs, and repeats, at most 5 rounds.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode (KeyboardKit 9.9.1, vendored and patched), SwiftUI,
XcodeGen, XCUITest, `xcrun simctl`, GitHub Actions macOS runner, Python 3 + Pillow for measuring.

**Source of truth:** this file for the visual campaign. `docs/plans/2026-10-28-ios-keyboard.md` stays the plan
of record for the keyboard's features (Sprint 6 is being planned there in parallel by the tower).

---

## Background the plane needs

- The phone build uses xtool on Linux (`ios-app/xtool.yml`, `ios-app/Package.swift`): a container app `Protly`
  and the keyboard extension `ProtlyKeyboard`, logic in the local package `ios-app/ProtlyCore`, UI on
  KeyboardKit 9.9.1 vendored at `ios-app/Vendor/KeyboardKit` with `protly.patch` and `VENDORED.md` listing every
  change from upstream. Never break that build: do not edit `ios-app/Package.swift` or `ios-app/xtool.yml`.
- `ios-app/Sources/ProtlyKeyboard/Secrets.swift` is gitignored and absent in CI. CI writes a stand-in with the
  same shape as `ios-app/scripts/make-secrets.sh` output: `enum Secrets { static let apiKey = "" }`. The keyboard
  types without it; only Translate/Polish need a key, and they are not screenshot here.
- Geometry targets (Apple's keyboard on an iPhone 13 Pro, iOS 26, portrait, measured from phone screenshots,
  all in points): band from the keyboard's top edge to the top of row 1 keys 52; row pitch 54; key height 43;
  side margin and gap 7.33; Apple's band under the last row 71, ours 74.83 (iOS draws the globe/mic band under a
  third-party keyboard and clips it to its view, accepted by the user). Constants live in
  `ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift` (`ProtlyGeometry`).
- What broke on the phone, newest last:
  1. Row 1 long-press bubbles were cut at the keyboard's top edge. Fixed in the vendored
     `Callouts+ActionCallout.swift` (bubble shrinks to fit the room above the key). Key pop-ups (input callouts)
     are off for the same reason.
  2. An empty left bar slot collapsed and Translate slid to the left quarter. Fixed in `ProtlyBar.swift`.
  3. The band above row 1 was 52 pt on first open and 35 pt after switching to Emoji and back: the view's own
     content was 239.5 pt and iOS sometimes added 17.5 pt above it. Commit 62a4d02 made the content itself 257 pt
     (`ProtlyGeometry.topBand`). On the phone the height is still unstable: "sometimes taller, sometimes
     shorter". Leading hypothesis: nothing pins the input view's height, so iOS picks a different height per
     presentation path (first open, Emoji round-trip, app switch). The usual fix is a height constraint on the
     controller's `view` (or `inputView`) with priority 999, set once the view exists, equal to the layout's total
     height; KeyboardKit's `KeyboardHostingController` pins the hosting view to the controller view's edges, so
     the SwiftUI content then fills an exact frame. Prove or disprove this with screenshots before relying on it.
- The repo is a Chrome extension too (`src/`, `tests/`, `npm test`). Leave it alone; `npm test` must stay green.

## Sprint 001: simulator screenshots, measurements, and layout fixes

**Files:**
- Create: `.github/workflows/keyboard-shots.yml`
- Create: `ios-app/CI/project.yml` (XcodeGen), `ios-app/CI/Host/` (host app sources and Info.plist),
  `ios-app/CI/UITests/` (XCUITest), `ios-app/CI/measure.py`, `ios-app/CI/README.md`
- Create if the height fix needs it: `ios-app/Sources/ProtlyKeyboard/ProtlyHeight.swift`
- Modify (fixes only, smallest change that passes): `ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift`,
  `ios-app/Sources/ProtlyKeyboard/ProtlyBar.swift`, `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`
  (view lifecycle and `ProtlyRoot` only; typing and actions code is out of scope),
  `ios-app/Vendor/KeyboardKit/**` (every change also lands in `protly.patch` and `VENDORED.md`)
- Append: `docs/ios-keyboard-notes.md` section `## Simulator verification`

**Stay out of the tower's way:** the tower is building Sprint 6 of the feature plan locally at the same time and
edits `ProtlyBar.swift` (right slot) and `KeyboardViewController.swift`. Put the height fix in `ProtlyHeight.swift`
with at most a one-line call from `KeyboardViewController`. Edit `ProtlyBar.swift` only if the 07 check fails.
Vendored KeyboardKit edits are for layout only. CI builds with an Xcode 26 SDK while the phone uses the iOS 27.1
SDK: never change vendored code to silence a CI-only SDK error; report it instead.

### Task 1: CI project that builds the keyboard for the simulator

1. `ios-app/CI/project.yml` for XcodeGen: target `ProtlyCIHost` (iOS app, bundle id
   `com.northprot.protly.cihost`, one SwiftUI screen with a single multi-line `TextField` focused on launch,
   accessibility id `field`, initial text from the launch argument `-prefill` when given, one solid background color
   that `measure.py` knows), target `ProtlyCIKeyboard` (app
   extension, bundle id `com.northprot.protly.cihost.keyboard`, sources `../Sources/ProtlyKeyboard`, Info.plist
   `../Support/ProtlyKeyboard-Info.plist` with `GENERATE_INFOPLIST_FILE: YES` so Xcode merges the bundle keys
   (`CFBundleIdentifier`, `CFBundleExecutable`, `CFBundlePackageType`, versions; xtool adds them on the phone build),
   Swift 5 language mode, local packages `../ProtlyCore` and
   `../Vendor/KeyboardKit`, embedded in the host), target `ProtlyCIUITests` (UI tests for the host).
   The keyboard's resources (word lists, `keyboard-prompt.txt`) come from ProtlyCore's package resources
   (`Bundle.module`) as in the xtool build; depending on the package product embeds them. Sign ad-hoc
   (`CODE_SIGN_IDENTITY: "-"`), not unsigned. Add `OTHER_LDFLAGS` only if the principal class is missing at
   runtime. `ios-app/CI/README.md` states that `project.yml` mirrors the dependencies in `ios-app/Package.swift`.
2. The workflow (macOS runner image with Xcode 26 and an iOS 26 simulator runtime; pick the newest GitHub-hosted
   image that has both and name it in the README) installs XcodeGen, writes the Secrets stand-in, generates the
   project, and builds for `iphonesimulator`. Trigger: `workflow_dispatch`, and `push` to branches other than
   `main` and `ci-shots` (paths `ios-app/**` and the workflow file). The job runs only when the head commit
   message contains `[shots]` (`if: contains(github.event.head_commit.message, '[shots]') ||
   github.event_name == 'workflow_dispatch'`), so ordinary commits cost nothing. `timeout-minutes: 40`; cache
   SwiftPM and DerivedData. `concurrency` cancels an older run on the same branch. Every run counts toward the
   budget in Task 4, build-fix runs included: macOS minutes on a private repo are scarce.
3. Done when the build step is green on the PR branch.

### Task 2: scenarios and screenshots

1. Simulator: iPhone 13 Pro if the runtime has it, else the first 390 pt wide iPhone; name the device in the
   report. Portrait, dark appearance (`xcrun simctl ui <udid> appearance dark`), English system language.
2. Enable the keyboard without the Settings UI: before the UI test, write the simulator's global
   `AppleKeyboards` to Protly, then Emoji, then Apple's English (US) keyboard (`xcrun simctl spawn <udid> defaults
   write -g AppleKeyboards -array ...`, plus `AppleKeyboardsExpanded -int 1`), then respring or reboot the
   simulator. Also set `DidShowContinuousPathIntroduction` and `KeyboardPrediction` to true. Before boot, run
   `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false` so the soft keyboard shows. If
   Protly still does not appear, add it by driving the Settings app in XCUITest (`com.apple.Preferences`) and
   document in the README which way worked. Full Access is not needed.
3. XCUITest scenarios, each saving a full-screen PNG through `XCUIScreen.main.screenshot()` as an attachment and
   copying it to a known output directory (the workflow collects it). Never use `typeText` or `app.keyboards` on
   Protly: `typeText` sends hardware-style key events that skip the extension, and Protly's SwiftUI keys are not
   in `app.keyboards`. Tap Protly keys and the system dock globe with `XCUICoordinate` at positions computed from
   `ProtlyGeometry` and the screen size. The UITests target cannot import `ProtlyGeometry` (it imports KeyboardKit); copy
   the constants it needs. Run 02 first with Protly as the current keyboard; run 01 last, picking
   English from the globe's long-press list.
   - `01-apple`: Apple's English keyboard on the field (reference geometry).
   - `02-first-open`: Protly on the field, first presentation.
   - `03-after-emoji`: switch to Emoji with the system globe/emoji key, then back to Protly.
   - `04-after-background`: `XCUIDevice.shared.press(.home)`, wait 2 s, `app.activate()`, keyboard up again.
   - `05-after-second-emoji`: a second Emoji round-trip.
   - `06-word-typed`: type `hello` then space: the bar's left slot shows the other reading and center shows the
     action.
   - `07-empty-left-slot`: relaunch the host with launch argument `-prefill "see you tomorrow"` (the host puts
     that text in the field). The left slot is empty and the center shows the action.
   Not here, checked by the tower on the phone: the row 1 long-press bubble (`press(forDuration:)` blocks, so no
   screenshot while held) and Hangul keycaps (the default, already in 02).
4. Done when all 7 PNGs land on `ci-shots` (see Task 3) for one run.

### Task 3: measure and publish

1. `ios-app/CI/measure.py <dir>` (Python 3, Pillow) finds in each PNG, in points (scale from the PNG width and
   the device's point width): keyboard top edge, top of row 1 keys, row pitch, key height, bar text center x.
   The host background is one solid known color. The keyboard top edge is the first row, scanning down the
   screen's center column, that differs from that color by more than 24 (sum of RGB) for 6 rows in a row. Row 1
   top: in the column of the second key, below the keyboard top edge, the first row that starts a run of at least
   30 pt differing from the keyboard background by more than 24 (keys are 43 pt tall, bar text is shorter). It prints one line per check and a final
   `RESULT PASS` or `RESULT FAIL`:
   - keyboard top edge identical (within 0.5 pt) across 02 to 07
   - band above row 1 within 1 pt of `01-apple`'s band
   - row pitch 54 and key height 43 within 0.5 pt
   - 07: the center slot's text centered within 2 pt of the screen's center x
2. The workflow commits the PNGs and `report.txt` (measure output plus device, runtime, Xcode version and the
   source commit sha) to the orphan branch `ci-shots` under `runs/<first 7 chars of GITHUB_SHA>-<run_number>/`,
   with `contents: write` permission and the default `GITHUB_TOKEN`. It never pushes to any other branch. The
   publish step runs with `if: ${{ !cancelled() }}` on every outcome, so a failed build is visible too: line 1 of
   `report.txt` is `STATUS build-failed`, `STATUS test-failed` or `STATUS measured`, and a failure includes the
   last 200 lines of the failing xcodebuild log. The push retries fetch, rebase, push up to 3 times. After
   publishing, the job fails unless the report says `RESULT PASS`. (Pushes made with `GITHUB_TOKEN` never start
   another workflow run.)
3. You may have no `gh` access; `ci-shots` is your view of every run. Read the shots with
   `git fetch origin ci-shots` and `git show origin/ci-shots:runs/<dir>/<file>`; look at the
   PNGs yourself (the Read tool shows images) before trusting the numbers. If a measurement is wrong, fix the
   script, not the target.

### Task 4: fix, re-run, repeat (at most 5 rounds)

1. Round = change the keyboard code, push a commit whose message contains `[shots]`, wait for the run, read
   report and PNGs. Wait = `git fetch origin ci-shots` every 3 minutes; if no `runs/<sha7>-*` appears 60 minutes
   after the push, report BLOCKED. Stop when `RESULT PASS` and the PNGs look right by eye against `01-apple`, or
   after round 5.
2. Start with the height hypothesis in Background item 3. Every fix keeps the phone build working: same
   sources, no simulator-only code paths in the keyboard (`#if targetEnvironment(simulator)` is not allowed).
3. At most 10 workflow runs in total for the sprint (macOS minutes are limited); say how many were used.
4. Append `## Simulator verification` to `docs/ios-keyboard-notes.md`: device, runtime, a table of the final
   measurements per scenario next to `01-apple`, what each round changed and what it fixed, and anything the
   simulator cannot show (for example behaviour that only a real device has).

**Sprint 001 done when:** the last run says `RESULT PASS`, the 7 PNGs on `ci-shots` match it by eye, `npm test`
passes, and the report lists the rounds. If 5 rounds do not reach PASS, deliver anyway as DONE_WITH_CONCERNS with
the remaining failures and the best hypothesis.
