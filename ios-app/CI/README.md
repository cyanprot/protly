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
5. `publish-shots.sh` commits the PNGs, the logs and `report.txt` to the orphan branch `ci-shots` under
   `runs/<sha7>-<run_number>/`, whatever the outcome. Line 1 of `report.txt` is `STATUS build-failed`,
   `STATUS test-failed` or `STATUS measured`; a failure ends with the last 200 lines of the failing log. The job
   then fails unless the report says `RESULT PASS`.

## Reading a run without GitHub access

    git fetch origin ci-shots
    git ls-tree --name-only origin/ci-shots runs/
    git show origin/ci-shots:runs/<dir>/report.txt
    git show origin/ci-shots:runs/<dir>/02-first-open.png > /tmp/02.png
