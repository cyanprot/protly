# Keyboard screenshots in CI

`.github/workflows/keyboard-shots.yml` installs the Protly keyboard in an iOS Simulator, screenshots it in the states
that broke on the phone, and measures the screenshots against Apple's keyboard in the same simulator. Plan:
`docs/plans/2026-10-29-keyboard-visual.md`. Results: `docs/ios-keyboard-notes.md`, "Simulator verification".

## When it runs

On a push to any branch but `main` and `ci-shots` that touches `ios-app/**` or the workflow, and only when the head
commit message contains `[shots]`; or by hand (`workflow_dispatch`). macOS minutes are scarce: batch changes.

Runner image `macos-26` (GitHub-hosted, arm64): Xcode 26.6 by default and iOS 26.x simulator runtimes. The
script takes the newest iOS 26 runtime and an iPhone 13 Pro (else the first 390 pt wide iPhone it can create).

## What it does

1. `project.yml` (XcodeGen) builds `ProtlyCIHost`, an app with one field on a solid color, embedding
   `ProtlyCIKeyboard` from `../Sources/ProtlyKeyboard` with the phone's `../Support/ProtlyKeyboard-Info.plist`.
   **It mirrors the ProtlyKeyboard target's dependencies in `ios-app/Package.swift`** (local packages
   `../ProtlyCore` and `../Vendor/KeyboardKit`, Swift 5 language mode): change both together. The phone build
   (xtool) never reads this folder. Signing is ad hoc (`-`). `Secrets.swift` is a stand-in with an empty key.
2. `run-shots.sh` creates the simulator, boots it once to install the app and set dark mode, then writes the
   keyboard list straight into the shut-down device's preferences (`AppleKeyboards` = Protly, Emoji,
   English (US); `AppleKeyboardsExpanded`; `KeyboardPrediction`; `DidShowContinuousPathIntroduction`) and boots
   again. If Protly still cannot be reached with the globe, the UI test adds it in Settings > General > Keyboard >
   Keyboards. `ui-log.txt` of each run says which way worked.
3. `UITests/KeyboardShotsUITests.swift` runs the scenarios in the order 02 to 07, then 01, and saves
   `NN-name.png`, `ui-log.txt` and `tree-*.txt` (the accessibility tree per keyboard) to the run folder. Protly's
   keys are tapped by coordinate (XCUITest cannot see a keyboard extension's views).
4. `measure.py <dir>` prints one line per screenshot, one line per check and `RESULT PASS` or `RESULT FAIL`.
   `test_measure.py` tests it on synthetic screenshots (`python3 -m unittest discover -s ios-app/CI -p 'test_*.py'`,
   needs Pillow).
5. `publish-shots.sh` (after `leak-guard.sh`) commits the PNGs, the logs and `report.txt` to the orphan branch
   `ci-shots` under `runs/<sha7>-<run_number>/`, whatever the outcome. Line 1 of `report.txt` is
   `STATUS build-failed`, `STATUS test-failed` or `STATUS measured`; a failure ends with the last 200 lines of the
   failing log. The job then fails unless the report says `RESULT PASS` (and, from the phone checks, no FAIL).

## Phone checks

`docs/plans/2026-10-30-sim-phone-checks.md` (results: `docs/ios-keyboard-notes.md`, "Simulator phone checks").
After the layout scenarios, `UITests/PhoneChecksUITests.swift` runs the phone checklists that need no network, in
the order `test0_probe` (only with `[probe]` in the commit message), `test1_68`, `test2_ws`, `test3_85offline`,
`test4_memory`, `test5_icon`; learned words carry over between them.

- `UITests/Driver.swift`: the shared helpers. Text is typed by coordinate: Hangul as its Dubeolsik keys
  (ProtlyCore `KeyEncoder`, linked into the UI tests), capitals and shifted jamo with a shift tap, symbols on the
  123 layer (positions from KeyboardKit's iPhone layout widths), `\n` with return. The host's `Clear` and
  `Dismiss` buttons empty the field and hide the keyboard; the field's text is read through XCUITest (exact).
- `UITests/Reader.swift`: Vision OCR of a bar slot inside the test. A self-test (Vision reads "Polish" and Hangul
  drawn by the test) is the positive control; a slot also gets an ink count (pixels far from the bar's
  background), so "empty" never rests on OCR alone. A missing reading is FAIL `unreadable`.
- `memsample.py` samples the `ProtlyCIKeyboard` process every 2 s from the macOS side (`mem.txt`; which memory
  method works is in `probe-mem.txt`). The test logs `MARK` lines in `ui-log.txt`.
- `checks.py` resolves 6.8-9 (relaunch) and 6.8-10 (memory) from the marks and samples, turns a missing or
  malformed line into FAIL `unreadable`, and writes the sorted `checks.txt` and the report's `CHECKS` section
  (`CHECKS pass N fail N record N skip N`). The test's own lines stay in `checks-raw.txt`.
- `ProtlyCIApp` is the container app built as xtool builds it (phone Info.plist, `AppIcon.png` at the bundle
  root), for the home-screen icon (`c-icon.png`).
- Every item saves `c-<id>.png`, and each slot reading `c-<id>-<n>-<slot>.png`.
- `leak-guard.sh` runs before every publish: a run folder with a key prefix in any file publishes only a
  `STATUS leak-guard` report and the step fails.

The job fails unless the report says `STATUS measured`, `RESULT PASS` and no `CHECK ... FAIL`.

## Reading a run without GitHub access

    git fetch origin ci-shots
    git ls-tree --name-only origin/ci-shots runs/
    git show origin/ci-shots:runs/<dir>/report.txt
    git show origin/ci-shots:runs/<dir>/02-first-open.png > /tmp/02.png
