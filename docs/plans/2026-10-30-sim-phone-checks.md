# Simulator Phone Checks Implementation Plan

> **For Claude:** cloud campaign. Planes implement one sprint each from a pasted brief; the tower verifies and lands.

**Goal:** Every phone check the user still owes (Tasks 6.8, 7.7, 8.5 of `docs/plans/2026-10-28-ios-keyboard.md`,
the flip-over-whitespace rule of 997f108, and the app icon) runs in the iOS Simulator on the GitHub macOS runner
instead of on the user's iPhone, with a machine-readable PASS / FAIL / RECORD / SKIP line per checklist item.

**Architecture:** The existing simulator job (`.github/workflows/keyboard-shots.yml`, `ios-app/CI/`, notes section
"Simulator verification" in `docs/ios-keyboard-notes.md`) gains a second XCUITest class, `PhoneChecksUITests`, that
types on Protly by coordinate, reads the host field's text through XCUITest (exact), reads the keyboard's bar and
panel text from screenshots with Vision OCR inside the test (or, if the probe run shows Vision does not work there,
pixel signatures), and measures the keyboard process's memory from the macOS side. Sprint 001 covers every check
that needs no network. Sprint 002 adds Full Access, an API key from a GitHub Actions secret, the container app, and
the Translate / Polish / Read clipboard checks.

**Tech Stack:** XCUITest, Vision (`VNRecognizeTextRequest`), `xcrun simctl`, XcodeGen, Python 3 for report
assembly, GitHub Actions `macos-26`, the orphan branch `ci-shots`.

**Source of truth:** this file for the simulator phone checks. `docs/plans/2026-10-28-ios-keyboard.md` stays the
plan of record for keyboard features; its Tasks 6.8, 7.7 and 8.5 are the checklists referenced below by ID, and
their "(USER)" steps are replaced by this campaign (each task there carries a one-line pointer here).
`docs/plans/2026-10-29-keyboard-visual.md` stays the record of the layout job this one extends.

---

## Background the plane needs

- Read `ios-app/CI/README.md` and `docs/ios-keyboard-notes.md` section "Simulator verification" first. They say how
  the job builds `ProtlyCIHost` with the keyboard, enables Protly through `AppleKeyboards` in the shut-down
  simulator's preferences, taps keys by coordinate (XCUITest cannot see an extension's views: never `typeText`,
  never `app.keyboards` for Protly, and no button inside the keyboard, including the panel's Insert / Undo / Save /
  Cancel / Done, is visible to XCUITest), publishes every outcome to `ci-shots` under `runs/<sha7>-<run>/`, and runs
  only for a head commit whose message contains `[shots]` (or `workflow_dispatch`).
- You have no macOS and usually no `gh`. Your view of a run is `git fetch origin ci-shots` and
  `git show origin/ci-shots:runs/<dir>/<file>`. Look at the PNGs yourself (the Read tool shows images).
- Never break the phone build: do not edit `ios-app/Package.swift` or `ios-app/xtool.yml`; no
  `#if targetEnvironment(simulator)` or other simulator-only paths in `ios-app/Sources/**`. This campaign changes
  no keyboard behaviour. If a check fails because the keyboard is wrong, record it as FAIL with what was seen and
  report it; do not fix keyboard code (the tower decides).
- `Words.showsMemory` stays `false`. Memory is measured from outside the process (Task 1.4).
- The keyboard types Korean by default on the QWERTY grid: Hangul is typed as its 2-beolsik keys (`안녕` is
  `d k s s u d`). `ios-app/ProtlyCore` has the encoder (`KeyEncoder`, text to keys). If the UITests target can link
  the ProtlyCore package product (it has no KeyboardKit dependency), use it; otherwise write the key sequences out
  by hand in the test with a comment giving the Hangul.
- **Language codes flip:** after typing any language code (`ru`, `zh`, `ja`, `es`, `ko`, `ok`) read the field. If
  it is not the Latin code, tap the left slot and note `flip` in that item's evidence. Learned words carry over
  between items, so whether a code needs the flip changes during the run; that is expected.
- **Order matters:** learned words persist across test methods. XCTest runs methods alphabetically; name them
  `test1_...`, `test2_...` so the order is fixed by design, and log the order in `ui-log.txt`.
- macOS minutes on this private repo are scarce. Each sprint has a run budget; build-fix runs count. Before every
  push run the Linux-side syntax checks in the verify command.

## Checklist IDs

Every checklist item gets one line in `checks.txt`:

```
CHECK <id> PASS|FAIL|RECORD|SKIP <one-line evidence: field text, OCR text, numbers>
```

PASS / FAIL are for items with a stated expectation. RECORD is for "record whether" items and anything the
simulator can only observe. SKIP names the reason (for example `no network key`). IDs are `6.8-1` ... `6.8-11`,
`ws-1` ..., `7.7-1` ..., `8.5-1` ..., `icon`. The item texts are in the feature plan's Tasks 6.8, 7.7, 8.5; this
plan says only how each is checked. A check whose evidence could not be read (no OCR text, no screenshot) is FAIL
with `unreadable`, never PASS.

---

## Sprint 001: offline phone checks

**Files:**
- Create: `ios-app/CI/UITests/PhoneChecksUITests.swift`, `ios-app/CI/UITests/Driver.swift`,
  `ios-app/CI/UITests/Reader.swift`, `ios-app/CI/checks.py`, `ios-app/CI/test_checks.py`
- Modify: `ios-app/CI/project.yml`, `ios-app/CI/Host/**` (Clear and Dismiss buttons), `ios-app/CI/run-shots.sh`,
  `ios-app/CI/publish-shots.sh`, `ios-app/CI/README.md`, `ios-app/CI/UITests/KeyboardShotsUITests.swift` (only to
  move shared helpers into `Driver.swift`), `.github/workflows/keyboard-shots.yml`
- Append: `docs/ios-keyboard-notes.md` section `## Simulator phone checks`

### Task 1.0: probe run (run 1 of the budget)

One `[shots]` run with a `test0_probe` method plus the `run-shots.sh` side of step 3 and the publish of its output.
It writes `probe.txt` and PNGs, and the rest of the sprint is built on what it finds. After the probe run,
`test0_probe` is skipped (keep it behind the launch environment `PROBE=1`) to save minutes:
1. `VNRecognizeTextRequest.supportedRecognitionLanguages()` inside the UITest (iOS Simulator), and the OCR text of
   a screenshot of Protly after typing `hello` space (bar) with `recognitionLanguages = ["ko-KR", "en-US"]`,
   `.accurate`, language correction off. Also one Hangul sample: type `안녕` (no space) and OCR the field's
   screenshot region.
2. Screenshot of the `123` layer (tap its key by coordinate), saved `probe-123.png`; the plane measures the colon,
   `?`, and `ABC` key centers from it.
3. The keyboard extension's process from the macOS side: `pgrep -x ProtlyCIKeyboard` (log all matches), then each
   of `footprint -p <pid>`, `sudo footprint -p <pid>`, `vmmap --summary <pid>`, `ps -o rss= -p <pid>`; log which
   ones print a number.
If Vision works in the test, Task 1.2 uses it there. If not, Task 1.2 falls back to pixel signatures.

### Task 1.1: shared driver, host buttons, the checks class

1. Move the coordinate typing, globe, focus, screenshot and log helpers of `KeyboardShotsUITests.swift` into
   `Driver.swift`. The 7 layout scenarios keep their names, order and `report.txt` format.
2. Host (`ios-app/CI/Host`, CI code): add a `Clear` button (id `clear`) that empties the field, and a `Dismiss`
   button (id `dismiss`) that sets the field's focus to false. Driver: `fieldText()` reads the field's `value`,
   `clearField()`, `dismissKeyboard()`.
3. `PhoneChecksUITests` with methods `test1_68`, `test2_ws`, `test3_85offline`, `test4_memory`, `test5_icon`. Each
   appends its `CHECK` lines to `$SHOTS_DIR/checks.txt` and saves a PNG per item named `c-<id>.png`; a failing group
   does not stop the others (`continueAfterFailure = true`).
4. Bar taps: the bar is the band above row 1 (52 pt, `Geo.band`); left, center and right slots are thirds of the
   screen width. `tapSymbol(_:)` taps the `123` layer keys at the positions measured in Task 1.0.

### Task 1.2: reading the bar and panel

1. `Reader.swift` (in the UITests target): `text(in rect: CGRect) -> [String]` runs Vision on
   `XCUIScreen.main.screenshot()` cropped to the rect, NFC-normalizes the lines, and logs them.
2. Prefer the field text over OCR whenever the item's effect shows in the field (tap a slot, then read the field).
   OCR is for what is only shown: slot labels before a tap, panel text.
3. Fallback only if Task 1.0 shows Vision fails in the simulator: compare a slot or panel region against a
   reference crop captured in the same run, and mark label checks RECORD with the crop saved.
4. `checks.py` (report assembly): sorts CHECK lines, counts them, and applies the script rules of Task 2.3 when
   002 adds them. `test_checks.py` (offline) tests the parsing, sorting, counts, that a malformed or missing line
   becomes FAIL `unreadable`, and that NFC and non-NFC Hangul compare equal.
   `checks.py` also resolves `PENDING` lines and 6.8-10 from the `MARK` lines in `ui-log.txt` and the pid samples in
   `mem.txt` (nearest timestamp); `test_checks.py` tests both, including the same-pid and changed-pid cases.

### Task 1.3: the checks

How each item is checked (item texts: feature plan Task 6.8 and Task 8.5; flip rule: commit 997f108):

| ID | Method |
|---|---|
| 6.8-1 | type `i dont think its ok teh.`: field equals it exactly. Clear, type `teh`: OCR right slot equals `the`; tap right slot: field `the ` |
| 6.8-2 | `recieve`: OCR right slot equals `receive`; type `.`: field `recieve.` |
| 6.8-3 | `tomo`: OCR right slot equals `tomorrow`; tap: field `tomorrow ` |
| 6.8-4 | `안녀`: OCR right slot starts with `안녕` (RECORD the text); clear, `안녕ㅎ`: tap right slot: field `안녕하세요 ` |
| 6.8-5 | RECORD: `omw`, OCR right slot, then space, field text (the simulator's text replacements may differ from a phone's) |
| 6.8-6 | SKIP `no contacts in the simulator` |
| 6.8-7 | each Korean phrase typed in one go: field equals the Hangul; then `I need to get rid of it`: field equals it |
| 6.8-8 | `wyd`: field `죵`; tap left slot: field `wyd`; space, clear, `wyd `: field `wyd ` |
| 6.8-9 | the test logs `MARK relaunch-before`, terminates the host, waits 2 s, relaunches, logs `MARK relaunch-after`, types `wyd ` and writes `CHECK 6.8-9 PENDING <field text>`. `checks.py` compares the pids nearest the two marks in `mem.txt` and writes the final line: PASS if the field matched and the pid changed; RECORD `same process` if the field matched with the same pid; FAIL if the field did not match |
| 6.8-10 | memory, Task 1.4 |
| 6.8-11 | flip part only: Korean draft, tap left slot, field shows the other reading. The Translate part is 002's |
| ws-1 | `hello` space: OCR left slot shows Hangul; tap it: field shows the Korean reading plus the space |
| ws-2 | `hello.` then space: left slot empty (OCR finds no text in the left third) |
| ws-3 | `hello` then return: left slot empty |
| 8.5-1o | `ru` at field start (flip rule), then `: ` and `누나 노트 고마워 누나 덕분에 살았다`: OCR center equals `Translate` |
| 8.5-2o | clear, `ru` again at the start: RECORD the field (Latin or Hangul). Then `zh` (flip rule), clear, `zh` and space at the start: RECORD whether the field shows `코 ` or `zh ` |
| 8.5-6o | `ok: 내일 봐`: OCR center equals `Translate` |
| 8.5-7o | `ko: 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠`: OCR center equals `Polish` |
| 8.5-8o | the three-paragraph `ko:` draft of 8.5 item 8: RECORD the center text |
| 8.5-9o | the Spanish draft of 8.5 item 9 on English keys: OCR center equals `Polish` |
| icon | Task 1.5 |

### Task 1.4: memory

1. `run-shots.sh` starts a sampler before `xcodebuild test`: every 2 s, `pgrep -x ProtlyCIKeyboard` and the method
   that worked in Task 1.0, appended with a timestamp to `mem.txt`. It stops after the tests.
2. `test4_memory` logs `MARK mem-start <time>`, then 30 times: tap `dismiss`, wait 1 s, focus the field, wait 1 s;
   then `MARK mem-end <time>`.
3. `checks.py` takes the samples nearest the marks. `CHECK 6.8-10` is RECORD with both numbers, the growth and the
   method. If the pid changed between the marks it is RECORD `pid changed, not comparable` (iOS may restart the
extension on dismissal; that is neither a keyboard nor a CI fault).
   The 40 MB limit and the 10 MB growth line are the tower's judgement on the device numbers, not this check's.

### Task 1.5: the app icon

1. Add a target `ProtlyCIApp` to `project.yml`, built the way xtool builds the phone app: sources
   `../Sources/Protly`, `INFOPLIST_FILE: ../Support/Protly-Info.plist` (it carries `CFBundleIconFiles`), no asset
   catalog, and a build phase that copies `../Support/AppIcon.png` to the bundle root. Bundle id
   `com.northprot.protly.ciapp`. Install it with the host.
2. `test5_icon` goes home, finds the `Protly` icon through
   `XCUIApplication(bundleIdentifier: "com.apple.springboard").icons["Protly"]` (swipe pages until found), saves the
   crop as `c-icon.png`. `CHECK icon RECORD <frame> <found|missing>`. The tower judges the crop by eye.

### Task 1.6: report, workflow, budget

1. `report.txt` keeps its first line and the layout `RESULT` line; a `CHECKS` section follows with every `CHECK`
   line sorted by ID and `CHECKS pass N fail N record N skip N`. `publish-shots.sh` publishes `checks.txt`,
   `probe.txt`, `mem.txt` and the `c-*.png` / `probe-*.png` files with the rest.
2. Leak guard (in 001, so it is in place before any key exists): `publish-shots.sh` refuses to publish the run folder
   if `grep -rlF 'sk-ant-' <folder>` matches anything, and publishes a `STATUS leak-guard` report instead (no files).
   It needs no secret. Unit test it in `test_checks.py` with a fake `sk-ant-test` file in a temp folder (call the
   guard as a function or a small script).
3. The job fails when the layout result is not PASS or any CHECK is FAIL. A FAIL caused by the keyboard is a
   finding, not a reason to change keyboard code.
4. Budget: at most 10 workflow runs for this sprint, run 1 being the probe.
5. Append `## Simulator phone checks` to `docs/ios-keyboard-notes.md`: device, runtime, the run directory, a table
   of every ID with its result and evidence, the probe findings (OCR, `123` layer, memory method), and "What the
   simulator cannot show" for these items.

**Sprint 001 done when:** the last `[shots]` run on the branch publishes `STATUS measured`, the layout says
`RESULT PASS`, every ID in Task 1.3's table has a CHECK line, no CHECK is FAIL for a reason in the CI code (a FAIL
on keyboard behaviour is allowed and reported), the verify command passes, and nothing under `ios-app/Sources`,
`ios-app/ProtlyCore`, `ios-app/Vendor`, `ios-app/Package.swift` or `ios-app/xtool.yml` changed.

---

## Sprint 002: network phone checks (Full Access, key, container app)

Depends on Sprint 001 (same files). Before dispatch the tower sets the repository secret `PROTLY_API_KEY` with
`gh secret set` from a local file. The key is a separate CI-only Anthropic key with a low monthly spend limit, not
the phone's key, and is revoked when this campaign closes: a repository secret reaches any branch push whose
commit carries `[shots]`, and the plane writes the code that handles it. The key never passes through a chat or a
brief. "No network calls in tests" in the brief covers the verify command; the simulator job's network checks are
this sprint's purpose.

**Files:**
- Modify: `ios-app/CI/UITests/PhoneChecksUITests.swift`, `ios-app/CI/UITests/Driver.swift`,
  `ios-app/CI/UITests/Reader.swift`, `ios-app/CI/run-shots.sh`, `ios-app/CI/publish-shots.sh`, `ios-app/CI/checks.py`,
  `ios-app/CI/test_checks.py`, `ios-app/CI/project.yml`, `ios-app/CI/README.md`, `.github/workflows/keyboard-shots.yml`
- Append: `docs/ios-keyboard-notes.md` section `## Simulator phone checks` (002 rows)

### Task 2.1: the key, safely

1. The workflow passes `secrets.PROTLY_API_KEY` as an env var only to the step that writes `Secrets.swift`. That
   step makes a `mktemp -d` folder, writes the key to `<tmp>/.config/protly/phone-api-key` with `umask 077`, runs
   `HOME=<tmp> ios-app/scripts/make-secrets.sh` (reusing its gitignore check), and deletes the folder. It never
   echoes the key and sets `HAS_KEY=true` in `$GITHUB_ENV` when the secret is non-empty. With no secret, the CI
   stand-in keeps an empty key and every network item is `SKIP no network key`.
2. Cache: with `HAS_KEY=true` the job only restores the cache (`actions/cache/restore`); it saves the cache
   (`actions/cache/save`) only when `HAS_KEY != 'true'`, so no DerivedData that holds the key is ever cached.
3. The 001 leak guard (`sk-ant-`) stays in front of every publish; the build log tail in `report.txt` is inside the
   guarded folder.
4. Nothing prints request bodies or headers.

### Task 2.2: Full Access and paste

1. Full Access is needed for network and the clipboard. Run 1 of this sprint is a probe: enable it through the
   Settings UI in a `test0_probe` (General > Keyboard > Keyboards > Protly > Allow Full Access > Allow) and dump the
   device's preferences folder before and after (each dump after a `simctl shutdown`, so the preference daemon has
   written to disk) into `probe-prefs.txt` (`plutil -p` of changed files, done by
   `run-shots.sh` around the test). Later runs write the found key before boot; if none is found, keep the Settings
   UI path. Say in the README which way worked.
2. Allow Paste prompts: try `addUIInterruptionMonitor`, then tapping `Allow Paste` in the host's alerts; log which.
3. Clipboard content for a check is set by the test runner with `UIPasteboard.general.string = ...` right before
   the tap.

### Task 2.3: the network checks

Panel buttons are inside the keyboard: the test waits for a result by polling OCR of the panel region every 0.5 s
for the button label (`Insert`, `Save`), up to 30 s; the poll time is the timing. Insert / Undo / Save / Cancel /
Done are tapped by coordinate at positions measured from the probe run's panel screenshot. Inserted text is read
with `fieldText()`. Model output varies: each FAIL on model output gets one retry in the same run, both outputs in
the evidence; two FAILs is a FAIL.

Test note (fictional, fixed, never the user's): `I run Moonbeam Kiln (문빔 킬른), a pottery studio in Victoria.`

| ID | Method |
|---|---|
| 8.5-1 | `ru: 누나 노트 고마워 누나 덕분에 살았다` (flip rule), tap center: OCR panel contains `Translating` (screenshot at once); poll for `Insert`; OCR the panel: RECORD whether a Hangul back translation is shown; tap Insert: field has Cyrillic, no `ru:`, contains `спасла`; tap Undo: field equals the draft |
| 8.5-3 | `ja: 내일 시간 있어? 같이 밥 먹자 ㅋㅋ` -> Insert: field has kana or kanji, no `ㅋ`, no `lol` |
| 8.5-4 | `es: 나 오늘 너무 피곤해` -> Insert: field contains `cansado`, not `cansada` |
| 8.5-5 | `내일 3시에 봐` -> Insert: field is Latin, no Hangul |
| 8.5-6 | `ok: 내일 봐` -> Insert: Latin, no Hangul |
| 8.5-7 | `ko: 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠` -> center Polish, tap: panel contains `Polishing`; OCR the change line before Insert (RECORD); Insert: field is Hangul, contains `ㅋㅋ`, `돼`, `말해 줘` or `말해줘` (the auxiliary verb spaced, the standard, or joined; tower ruling 2026-10-31 after run 41), no `ko:` |
| 8.5-8 | the three-paragraph `ko:` draft -> center, tap: panel contains `Polishing`; Insert: Hangul, no `ko:` |
| 8.5-9 | the Spanish polish -> Insert: contains `color`, `compraste`, `jaja`; no `colour` |
| 8.5-10 | seconds from tap to `Insert` for 8.5-1, two tries: RECORD |
| 6.8-11 | Korean draft, tap center Translate, Insert: field is Latin |
| 7.7-1 | in `ProtlyCIApp`, the test runner sets `UIPasteboard.general.string` to the test note, long-presses the About me field and taps the edit menu's `Paste` (an in-app paste: no Allow Paste prompt; never `typeText`, which fails with Protly as the active keyboard); read the app's character counter through XCUITest; tap `Copy for the keyboard`: the button says `Copied`. In the app's own Test field, switch to Protly, tap `Read clipboard`, allow paste: OCR panel contains `Save as your About me note` and the counter's number; tap Save: contains `About me saved`; tap Done: the bar is back (OCR center shows a bar label or nothing, no panel text) |
| 7.7-2 | in the host, `우리 문빔 킬른 다음 주에 오픈해` -> Translate -> Insert: field contains `Moonbeam Kiln`, contains neither `pottery` nor `Victoria` |
| 7.7-3 | pasteboard `Can you send me the photos from yesterday?`, empty field, Read clipboard: panel has Hangul. Then pasteboard `protly about me v1` + newline + `test`, Read clipboard: panel contains `(4 characters)`; tap Cancel; repeat 7.7-2: still `Moonbeam Kiln` |
| 7.7-4 | seconds from tap to `Insert` for 7.7-2, two tries: RECORD |
| 7.7-5 | in the app, clear About me, Copy, then Read clipboard in the app's Test field: panel contains `Clear your About me note`; Save: contains `About me cleared`; then redo 7.7-1's copy and save |
| 7.7-6 | SKIP `needs a phone reinstall` |

Script rules in `checks.py`, each unit-tested: Cyrillic = any U+0400..U+04FF; Hangul = any U+AC00..U+D7A3 or
U+3131..U+318E; kana or kanji = any U+3040..U+30FF or U+4E00..U+9FFF; Latin = at least one A-Z/a-z and no Hangul.

### Task 2.4: budget and report

1. At most 10 workflow runs for this sprint (run 1 the probe), and at most 60 API requests per run: the test
   counts taps that send, and above 60 SKIPs the rest with `request cap`.
2. Extend the notes table with 002's rows, the timings, and the Full Access and paste findings.

**Sprint 002 done when:** the last `[shots]` run with the secret present publishes `STATUS measured`, layout
`RESULT PASS`, every 002 ID has a CHECK line, the leak guard ran and passed, the cache was not saved in that run,
the verify command passes, and the keyboard and phone build files are unchanged as in Sprint 001.

---

## What stays off the simulator

Not checklist items for the user; the tower watches them on the phone in normal use when it matters: other host
apps (Messages, KakaoTalk, Instagram), the phone's iOS build and SDK, the 40 MB jetsam limit and real memory
numbers, a reinstall keeping the note (7.7-6), contact names (6.8-6), iPhone text replacements if 6.8-5 differs,
typing feel and haptics, the icon on the real home screen.
