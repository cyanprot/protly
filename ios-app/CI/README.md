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
still FAILs, and a selected entry with no passing test case (skipped, renamed, zero tests run) makes the run
`test-failed`. A filter that measures nothing (`test0_access` or `test0_probe` alone) is refused, and so is a message
with both `[shots]` and a `[shots:...]` tag. The judge step prints `FILTERED RUN ...` in its log and the job summary.
Filtered runs are outside the sprint's run budget; the run that closes a sprint is a full `[shots]` run with the key
unless the tower rules otherwise (sprint 002 closed on a filtered run, TOWER-CLOSE-RULE-2).

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
`test2_ws`, `test3_85offline`, `test4_memory`, `test5_icon`, the typing-fixes methods `test5a_web`, `test5b_menu` and
`test5c_pad`, the keyboard-ui methods `test5d_card` and `test5e_bar` (below), then the network groups `test6_85net` and
`test7_77` (below); learned words carry over between them.

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
- **The strip, the card and the panels** (keyboard-ui 003) are read from the host's accessibility tree, where the
  keyboard's SwiftUI views appear with their labels and frames (`UITests/KeyboardTree.swift`; the views carry the
  identifiers `protly-strip`, `protly-card` and `protly-panel`, which nothing speaks). A call: the strip's verb
  (`Translating`) right after the tap, then the tree every 0.5 s (up to 30 s) until the card's `Replace` (Read: `Insert`)
  is there and the strip is gone, since the card streams in and its buttons are there, inert, from the first words;
  Retry, an error line on the strip or a card without the strip and without `Replace` ends it as failed. The poll
  time is the timing (`seconds#n`; `first#n` is the first streamed words). Replace, Cancel and Done are tapped at
  their tree frames, 0.6 s after the card is finished (the card ignores taps for 0.5 s after it appears). The About
  me confirm and notice panels (Save, Cancel, Done) are found in the tree too; Vision OCR of the panel's bottom 45 pt
  (case-insensitive: Vision reads the semibold `Insert` as `insert`) stays the fallback.
- **Deadlines.** Each method has an XCTest time allowance (`PhoneChecksUITests.allowance`, `-test-timeouts-enabled`),
  the network groups stop starting items two minutes before theirs, `run-shots.sh` stops the main test run after
  65 minutes (`with_deadline`; run 53, on a slow runner, ran past the earlier 50 in test7_77), and the build
  step's 85-minute timeout (job: 95) leaves the publish steps time to run. The
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

## Typing-fixes checks (typing-fixes 004)

Plan section "Sprint 004" of `docs/plans/2026-10-30-typing-fixes.md`; results in `docs/ios-keyboard-notes.md`,
"Simulator proof (typing-fixes 004)". Code: `UITests/TypingChecks.swift`. Three offline methods run after
`test5_icon` and before the network groups. Every line is `PENDING` with its readings and `checks.py` decides
(`resolve_dark`, `resolve_ret`, `resolve_menu`, `resolve_menu4`, `resolve_pad`, unit-tested in
`test_typing_checks.py`).

- **Host screens.** `-screen <name>` on the host's command line (`PhoneRun(..., arguments:)`) picks a screen; none is
  the solid field above. Each keeps its content above 30% of the height (measure.py's background sample), with
  `Clear` and `Dismiss` top right, and publishes its readings as the accessibility values of small `Probe` captions
  (exact, unlike OCR). `-screen uikit`: a `UITextView` with `sel` (`location,length`), `marked`, `first-word` and
  `last-word` (frames in screen points). `-screen web`: a `WKWebView` with the bundled `Host/web-composer.html` (black,
  `color-scheme: dark`): a `<textarea>`, an `<input>` in a `<form>` whose submit is logged and prevented, and a
  `contenteditable` Enter-to-send composer with the `isComposing || keyCode === 229` guard and `caret-color:
  transparent`. `web-state` holds the fields' text, the sent and submitted lists, each field's text when the page
  saw Return, and a trace of the step's events; `web-rects` the fields' frames. Every DOM event is a line in the
  host's `Documents/web-events.txt` (`t=` epoch ms; the test's `MARK ret-<step>-<field>` lines in `ui-log.txt` use
  the same clock), which `run-shots.sh` copies into the run folder.
- **test5a_web**: row 1 is measured on the solid host first (on the web screen the form accessory bar sits above
  the keyboard), then the web screen. `dark-1`: `dkssud` (안녕) in the composer, a screenshot, a space, a screenshot;
  checks.py compares the ink inside the composer (count and tone) and looks for an underline row.
  `ret-<step>-<field>`: steps 1 to 5 of `enter-clears-web.md` in each field; the last tap (Return) follows after
  `gap` (0.05 s, or 0.3 s in step 4; XCUITest's own time to tap comes on top, the line says what it was). The
  field's text when the page saw Return must be the text typed; no Return event, or a form input that did not
  submit, is FAIL. A step that asked for Return at once but got it later than 0.3 s is RECORD, not PASS: it shows
  the text kept, not the at-once race (XCUITest taps about 0.6 s apart: runs 87ef63d-73 and 49bc717-74 measured
  0.6 to 1 s), which stays a phone check. Expect RECORD on ret-1, -2, -3 and -5 in every run.
- **test5b_menu** (`-screen uikit`): `menu-0` on Apple's keyboard (the control: keys tapped by label, then a
  double-tap on `hello`), `menu-1` on Protly (`안녕 오늘` with no space, a double-tap on `오늘`), `menu-4` (then `ㅎ`).
  The menu's items are found by label (none may be open before the double-tap); the tree is `tree-edit-menu.txt`.
  The rule also needs the field's text and the selection of the double-tapped word (`0,5`, `3,2`). `menu-4` reading
  `안녕 g` (the key read as Latin, still a replacement) is RECORD.
- **test5c_pad** (`-screen uikit`): `Driver.dragSpace` holds space 1 s, then drags in a straight line
  (`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`). `pad-1` 90 pt left, `pad-2` 90 pt left while
  rising 80 pt (must move at least 75% of pad-1), `pad-3` `안녕` and 20 pt left (one syllable: `1,0`). pad-1 must
  move at least 8 characters; the drag must leave the text as typed (a lost tap is retyped once) and no marked text.

## Result card checks (keyboard-ui 003)

Plan Task 3.5 of `docs/plans/2026-10-30-keyboard-ui.md` (design Part 3, CI list); results in
`docs/ios-keyboard-notes.md`, "Streaming result card (keyboard-ui 003)". Code: `UITests/CardChecks.swift`. Two offline
methods after `test5c_pad`; every line is `PENDING` with its readings and `checks.py` decides (`resolve_card_*`,
`resolve_mem_stream`, `resolve_hit`, `resolve_bar_look`, `resolve_bar_xxl`, `resolve_app`, unit-tested in
`test_card_checks.py`).

- **The stub.** `project.yml` sets the compilation condition `PROTLY_CI_STUB` on `ProtlyCIKeyboard` only (never
  `ios-app/Package.swift`, so the phone has no stub; a source rule in `KeyboardSourceRulesTests` keeps it so).
  `../Sources/ProtlyKeyboard/StubActionClient.swift` answers a draft that starts with `protly-stub <scenario>` with a
  recorded stream of server-sent events, through the same ProtlyCore driver as the real reply, before the key is read;
  every other draft goes to the API as on the phone, so the network checks are unchanged. Scenarios: `ok` (a thinking
  block, 2.8 s of waiting, the translation in 0.8 s deltas, the back translation), `slow` (pings past the strip's 8 s
  line, then 13 one-second deltas), `error` (an `overloaded_error` event before any text), `cut` (part of the
  translation, then the same error). The texts are repeated in `CardChecks.swift`'s `Stub`;
  `test_card_checks.py` compares the two files.
- **Drafts.** The host's `-fills "a|b"` adds buttons `fill-1`, `fill-2` (top right, above 30% of the height) that put a
  draft in the field with the keyboard up, so no relaunch is needed per call. The stub drafts end in Korean, so the
  bar offers `→ English`.
- **The looks helper.** The tests run inside the simulator and cannot call `simctl`: `Driver.looks` writes
  `<n> appearance light|dark` or `<n> content_size <size>` to `looks-requests.txt`, and `run-shots.sh`'s
  `looks_helper` runs `xcrun simctl ui <device> ...` and answers in `looks-acks.txt` (anything else is refused).
  `looks-changed.txt` remembers a look left changed, and the next method puts dark and the default size back.
- **test5d_card**, in dark then light: `card-wait-*` (the strip names `Translating → English…`, its xmark at least
  44 x 44 pt, no card), `card-mid-*` (the first words are the start of the result while the strip runs),
  `card-done-*` (the whole translation and back translation, Cancel, Copy and Replace at least 44 pt tall, the strip
  gone; dark taps Replace and the field takes the result, light taps Copy (Copied) and Cancel), `card-err0-*` (the
  error line on the strip with Retry, no card), `card-err1-*` (the kept text with the error line under it, Copy and
  Retry, no Replace). Then, dark: `card-slow` (`Still translating…` after 8 s), `mem-stream` (the keyboard's footprint
  from before the call through the long stream: at most 10 MB of growth; the 40 MB limit is the phone's) and
  `card-cancel` (the strip's xmark mid-stream closes everything, a later delta brings nothing back, the draft stays).
  Each item's `c-<id>.png` is the screen at the moment it was read.
- **test5e_bar**: `hit-1` (with `teh` typed, each of the three slot buttons at least 120 x 40 pt), `bar-dark` and
  `bar-light` (the bar with `teh`, then the `→ English` pill, in each look: checks.py measures the keyboard's
  background beside the bar and the paper or ink pixels in the center slot), `bar-xxl` (the extra-extra-large text
  size with `ms:` (Bahasa Melayu) and `ar:` (العربية): every part of the pill inside its slot and the arrow before the
  name; RECORD when the OCR shows the long name cut short or the text did not grow), `app-dark` and `app-light`
  (`ProtlyCIApp`'s guide screen: the hero line, and an ink or paper background; `c-app-<look>-1.png` and `-2.png` one
  screen down).

## Reading a run without GitHub access

    git fetch origin ci-shots
    git ls-tree --name-only origin/ci-shots runs/
    git show origin/ci-shots:runs/<dir>/report.txt
    git show origin/ci-shots:runs/<dir>/02-first-open.png > /tmp/02.png
