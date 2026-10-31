# Keyboard screenshots in CI

`.github/workflows/keyboard-shots.yml` installs the Protly keyboard in an iOS Simulator, screenshots it in the states
that broke on the phone, and measures the screenshots against Apple's keyboard in the same simulator. Plan:
`docs/plans/2026-10-29-keyboard-visual.md`. Results: `docs/ios-keyboard-notes.md`, "Simulator verification".

## When it runs

On a push to any branch but `main` and `ci-shots` that touches `ios-app/**` or the workflow, and only when the head
commit message contains `[shots]` or `[shots:...]`; or by hand (`workflow_dispatch`). macOS minutes are scarce:
batch changes. Put the tag on every fix push that should be tested: a push without it runs nothing.

### Debug runs: `[shots:...]`

`[shots:<entry>,<entry>...]` runs only those tests (`xcodebuild -only-testing`). An entry is a class
(`KeyboardShotsUITests`, `PhoneChecksUITests`) or a class and method (`PhoneChecksUITests/test7_77`).
`shotsfilter.py` checks every entry against the known methods and refuses a typo (`STATUS bad-filter`, before the
build). A selected `PhoneChecksUITests` method always brings `test0_access` first, since the network and clipboard
methods need the Full Access it sets. The report's second block has a `FILTER ...` line; the layout `RESULT` is
`NOT-RUN` unless `KeyboardShotsUITests` is selected, and every ID of an unselected method is `CHECK <id> NOT-RUN`
(`checks.py --ran`, counted as `not-run N` on the `CHECKS` line), not FAIL. A selected method that writes no line
still FAILs. Filtered runs are outside the sprint's run budget. The run that closes a sprint stays a full `[shots]`
run with the key. `[shots:...]` wins when a message carries both tags.

A method is the smallest unit: items inside one depend on each other (6.8-9 on the word 6.8-8 teaches, 8.5-10 and
7.7-4 on earlier timings, 7.7-3 repeats 7.7-2). Across methods, each phone method sets its own context (6.8-7 and
8.5-9o type a Korean or English word first; the `ru`/`ko` flips accept either first outcome), so a method run alone
checks the same thing, but the keyboard has not learned the words earlier methods taught: compare a filtered
result with a full run before calling it fixed. The memory sampler starts at the first selected phone method. A new
push with either tag cancels a run in progress on the branch, and the workflow sees a tag anywhere in the head
commit message: a message that only describes the syntax starts a run too (b784f28 did: `bad-filter`, and it
cancelled the full run in progress). Name the syntax in a commit message without its opening bracket.

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
After the layout scenarios, `UITests/PhoneChecksUITests.swift` runs the phone checklists in the order
`test0_access`, `test0_probe` (only with `[probe]` in the commit message; Sprint 002's probe since then), `test1_68`,
`test2_ws`, `test3_85offline`, `test4_memory`, `test5_icon`, then the network groups `test6_85net` and `test7_77`
(below); learned words carry over between them.

- `UITests/Driver.swift`: the shared helpers. Text is typed by coordinate: Hangul as its Dubeolsik keys
  (ProtlyCore `KeyEncoder`, linked into the UI tests), capitals and shifted jamo with a shift tap, symbols on the
  123 layer (positions from KeyboardKit's iPhone layout widths), `\n` with return. The host's `Clear` and
  `Dismiss` buttons empty the field and hide the keyboard; the field's text is read through XCUITest (exact).
- `UITests/Reader.swift`: Vision OCR of a bar slot inside the test. A self-test (Vision reads "Polish" and Hangul
  drawn by the test) is the positive control; a slot also gets an ink count (pixels far from the bar's
  background), so "empty" never rests on OCR alone. A missing reading is FAIL `unreadable`; only with
  `OCR_FALLBACK=1` in the job's environment (for a runner where the self-test fails) do label checks RECORD the
  saved crop instead. Run 8's probe showed Vision works, so it is off.
- `memsample.py` samples the `ProtlyCIKeyboard` process every 2 s from the macOS side (`mem.txt`; which memory
  method works is in `probe-mem.txt`). The test logs `MARK` lines in `ui-log.txt`.
- `checks.py` resolves 6.8-9 (relaunch) and 6.8-10 (memory) from the marks and samples, turns a missing or
  malformed line into FAIL `unreadable`, and writes the sorted `checks.txt` and the report's `CHECKS` section
  (`CHECKS pass N fail N record N skip N`). The test's own lines stay in `checks-raw.txt`.
- `ProtlyCIApp` is the container app built as xtool builds it (phone Info.plist, `AppIcon.png` at the bundle
  root), for the home-screen icon (`c-icon.png`).
- Every item saves `c-<id>.png`, and each slot reading `c-<id>-<n>-<slot>.png`.
- A keyboard whose keys XCUITest can see, other than English and Emoji, is `system-keyboard`: iOS shows Apple's
  Korean keyboard while Protly is slow to start (runs 12 and 14). The tests wait up to 20 s for Protly to take
  over; a bar reading on anything but Protly is FAIL `unreadable`.
- `leak-guard.sh` runs before every publish: a run folder with a key prefix in any file publishes only a
  `STATUS leak-guard` report and the step fails.

The job fails unless the report says `STATUS measured`, `RESULT PASS` and no `CHECK ... FAIL`.

## Network phone checks (Sprint 002)

Plan section "Sprint 002" of `docs/plans/2026-10-30-sim-phone-checks.md`. The methods `test0_access` (first),
`test6_85net` and `test7_77` (last, after every offline group) add Full Access, Translate / Polish / Read clipboard
and the container app's about-me note: 6.8-11 (its Translate part runs inside `test1_68`), 8.5-1 and 8.5-3 to
8.5-10, 7.7-1 to 7.7-6. Code: `UITests/NetworkChecks.swift`.

- **The key.** The repository secret `PROTLY_API_KEY` (a CI-only key) reaches one step, `Write Secrets.swift`:
  `write-secrets.sh` writes it with `umask 077` to `<mktemp -d>/.config/protly/phone-api-key`, runs
  `HOME=<that folder> ios-app/scripts/make-secrets.sh` (which refuses unless `Secrets.swift` is gitignored) and
  removes the folder; it never prints the key and sets `HAS_KEY` in `$GITHUB_ENV`. With no secret every network
  item is `SKIP no network key` (7.7-1 and 7.7-5 need only Full Access and still run).
- **The cache.** `actions/cache/restore` runs before `Secrets.swift` exists; `actions/cache/save` runs only when
  `HAS_KEY == 'false'`, so a DerivedData that holds the compiled key is never cached. `report.txt` says which.
- **The leak guard** still runs before every publish (the build log tail is inside the guarded folder) and adds
  `LEAK-GUARD pass: ...` to the published report. Nothing prints a request, a header or a response body: the panel
  shows protly's fixed error messages only.
- **Full Access: the Settings UI way works** (run 40: "switch tap 2, Allow in the alert"). `test0_access` opens
  Settings > General > Keyboard > Keyboards > Protly, turns on Allow Full Access and taps Allow; the outcome is in
  `network.txt` and `full-access.txt`. iOS 26 Settings: rows are matched as cells by their own label or a labeled
  button inside them (root rows have no label of their own; General > Keyboard is titled "Keyboards", like its row),
  and scrolled into view either way. The probe found no preference key for it: `probe-prefs.txt` (a lone
  `test0_access` between two snapshots of the shut-down device, `prefsdump.py`) shows no plist change naming
  Protly or Full Access, and run 40 read TCC.db without its `-wal` file (copied since), so nothing is written
  before boot.
- **Panel buttons** (Insert, Undo is the bar's center, Save, Cancel, Done, Retry) are inside the keyboard: the test
  polls Vision OCR of the panel every 0.5 s (up to 30 s) and taps the label's word box from the same screenshot,
  in the panel's bottom 45 pt so the same word in the panel's text does not count, and case-insensitively (Vision
  reads the semibold `Insert` as `insert`). Polls read only that band (a whole-panel reading takes seconds); the poll
  time is the timing.
- **Deadlines.** Each method has an XCTest time allowance (`PhoneChecksUITests.allowance`, `-test-timeouts-enabled`),
  the network groups stop starting items two minutes before theirs, `run-shots.sh` stops the main test run after
  50 minutes (`with_deadline`), and the build step's 72-minute timeout leaves the publish steps time to run. The
  step log prints each method, each CHECK's ID and status, request counts and a heartbeat.
- **Allow Paste.** The prompt is a SpringBoard alert. The test taps `Allow Paste` in SpringBoard and touches nothing
  of the app under test meanwhile: the keyboard is blocked in its clipboard read until the prompt is answered, and a
  query of the host then waits on the keyboard's view (run 41: 3 x 60 s, and XCTest failed the method). The
  interruption monitor counts when it answers first (run 40's probe). `network.txt` logs which. A read that shows no
  panel relaunches the app, so a keyboard blocked on an unanswered prompt is freed.
  The test runner sets the clipboard with `UIPasteboard.general.string` with the keyboard down, then brings it back
  on the empty field, so the bar's center offers `Read clipboard`.
- **The container app** (`ProtlyCIApp`): the note is pasted into About me from the edit menu (no `typeText`), the
  counter is read through XCUITest, Copy for the keyboard, then Read clipboard in its Test field. Row 1 comes from
  the host's last measurement (the Form is not a solid color); the Form is dragged so no tap lands on the keyboard.
- **Model output** goes into the CHECK line as `out#1="..."` (and `out#2` after the one retry; `panel#n` for 7.7-3's
  Read clipboard). The test writes `PENDING`, and `checks.py` applies the script rules (`RULES`: Cyrillic, Hangul,
  kana or kanji, Latin, contains / lacks) and writes PASS or FAIL. Steps the test judges itself (the typed draft,
  the center's label, `Translating` at once, Undo, the confirm panel's count) make the line FAIL directly.
- **Request cap**: at most 60 requests per run (`requests:` in `network.txt`); above it items are `SKIP request cap`.
- The fictional test note: `I run Moonbeam Kiln (문빔 킬른), a pottery studio in Victoria.`

## Reading a run without GitHub access

    git fetch origin ci-shots
    git ls-tree --name-only origin/ci-shots runs/
    git show origin/ci-shots:runs/<dir>/report.txt
    git show origin/ci-shots:runs/<dir>/02-first-open.png > /tmp/02.png
