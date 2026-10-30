# Typing Fixes Implementation Plan

> **For Claude:** cloud campaign. Planes implement one sprint each from a pasted brief; the tower verifies and lands.

**Goal:** Fix four problems the owner hits in daily use of the Protly keyboard, plus the Spanish flip found by the
simulator checks:

1. Return in Safari or Chrome sometimes deletes the message.
2. The iOS edit menu (Copy, Paste) sometimes does not appear for selected text.
3. The word being typed (underlined) is sometimes invisible on dark screens.
4. Space bar cursor control feels worse than Apple's keyboard.
5. Spanish words typed after English flip to Hangul (check 8.5-9o).

**Architecture:** Problems 1 to 3 share one root: Protly keeps every word as host marked text
(`setMarkedText`) until it is committed. Sprint 001 removes marked text. The keyboard writes the word as plain
text and changes it by deleting and retyping only the changed tail, as Apple's Korean keyboard does.
`TypingSession` and its `FieldEdit` values stay as they are; only the way the keyboard writes them changes. The
decision logic moves into ProtlyCore as pure functions with unit tests. The field-move check gains the selection
rule from the edit-menu research. Sprint 002 changes one rule in `LanguageDetector`. Sprint 003 replaces
KeyboardKit's space drag math with Protly's own. Sprint 004 extends the simulator CI host with dark and web
fields and proves 1 to 4 there.

**Tech Stack:** Swift (ProtlyCore package, `swift test` on Linux), the keyboard target (UIKit, KeyboardKit
9.9.1 vendored), XCUITest and the keyboard-shots workflow on `macos-26`, Python for `checks.py`.

**Source of truth:** this file for these fixes. The research behind each sprint is in `docs/research/`:

| Sprint | Research |
|---|---|
| 001 | `2026-10-30-marked-text-dark.md` (option A, the recommendation), `2026-10-30-edit-menu-missing.md` (F1, H3), `2026-10-30-enter-clears-web.md` (C1 to C3) |
| 002 | `2026-10-30-spanish-flip.md` (option 2) |
| 003 | `2026-10-30-space-trackpad.md` (R1, R3, R4) |
| 004 | the "Simulator scenario" sections of all four |

`docs/plans/2026-10-28-ios-keyboard.md` stays the plan of record for keyboard features. `docs/ios-keyboard-notes.md`
records phone and simulator findings. `docs/plans/2026-10-30-sim-phone-checks.md` stays the record of the
simulator check harness this campaign extends.

---

## Background the plane needs

- Read the repo `CLAUDE.md`, then `docs/ios-keyboard-notes.md` (at least the Sprint 2 and Sprint 4 phone tables
  and the sections "Simulator verification" and "Simulator phone checks"), then the research doc(s) for your
  sprint.
- **Swift.** `swift test --package-path ios-app/ProtlyCore` must pass. If the session has no Swift toolchain,
  install one (swiftly, or the swift.org Linux tarball for Swift 6.x) before writing code. If that fails, stop and
  report BLOCKED; do not skip the Swift tests.
- **The keyboard target does not build on Linux** (UIKit, KeyboardKit). It is compiled by the keyboard-shots
  workflow on macOS. A push to any branch other than `main` whose head commit message contains `[shots]` runs it
  and publishes the result to the orphan branch `ci-shots` under `runs/<sha7>-<run>/`. Read the result with
  `git fetch origin ci-shots` and `git show origin/ci-shots:runs/<dir>/report.txt` (and `checks.txt`,
  `build.log` if present, PNGs with the Read tool). Each sprint below has a run budget; build-fix runs count.
  Wait for a run to publish before pushing the next `[shots]` commit (a new one cancels the running one).
- **Known flake:** `band-04-after-background` sometimes measures 69 instead of 52 (runs `b390712-8`,
  `307483a-12`). A run whose only failing layout check is that one counts as layout PASS for this campaign. If a
  run fails for a reason unrelated to your change (a simulator boot or XCTest harness failure, not a check your
  code affects), push one empty `[shots]` commit to re-run it; that re-run does not count against the budget. Say
  so in the report.
- Put logic in ProtlyCore wherever possible, as pure functions or value types, so it is unit tested on Linux. Keep
  the keyboard-target change thin: it calls ProtlyCore and talks to `textDocumentProxy`.
- Never break the phone build: do not edit `ios-app/Package.swift`, `ios-app/xtool.yml` or anything under
  `ios-app/Vendor/`. No `#if targetEnvironment(simulator)` paths in `ios-app/Sources/**`.
- `KeyboardSourceRulesTests.swift` reads the keyboard sources as text and enforces rules about them. Keep it
  passing and extend it where a sprint says so.
- Haptics stay off: the owner keeps them off, and a keyboard cannot read the system switch
  (`KeyboardViewController.swift` `viewDidLoad`). Do not add the trackpad haptic the space research suggests (R2).

## Sprint 001: plain-text composition (no marked text)

Fixes 1 to 3 at the root. `TypingSession` logic and its existing tests stay unchanged (a doc comment on
`FieldEdit.mark` that says "marked" may be reworded). Files: `ios-app/ProtlyCore/**`, `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`,
`docs/ios-keyboard-notes.md`. Run budget: 4 `[shots]` runs.

### Task 1.1: `PlainWord.edit` in ProtlyCore

New file `ios-app/ProtlyCore/Sources/ProtlyCore/PlainWord.swift`: `PlainWord.edit(from old: String, to new:
String) -> (deleting: Int, inserting: String)`. It deletes the characters (grapheme clusters) after the common
prefix and inserts the rest of `new` (sketch in `marked-text-dark.md` section 5).

Tests (`PlainWordTests.swift`), failing first:
- the six cases listed in `marked-text-dark.md` section 5 "Unit tests";
- a `FakeField` (a String that deletes Characters from the end and appends) and a replay property: for every
  key sequence in `TypingSessionTests.swift` and `SuggestionSessionTests.swift` (at least: 안녕하세요, hello
  after Korean, backspace inside 안녕, a flip while typing, `accept()` of a suggestion), applying each `FieldEdit` through `PlainWord` to the field leaves
  exactly `wordStart + markText` after each key and `wordStart + commitText` at the end;
- deletes never exceed the length of the previous written word (no edit reaches text before the word).

### Task 1.2: `FieldWatch.decide` in ProtlyCore

New file `FieldWatch.swift`: the field-move decision that `noticeFieldMoved` makes today
(`KeyboardViewController.swift:160-174`), as a pure function. With plain text, the word being typed is now
inside `documentContextBeforeInput`, so the rule changes from "context equals the text before the word" to
"context ends with the text before the word followed by the word Protly wrote".

The state FieldWatch reads, kept by the keyboard:
- `start`: the text before the word, **as Protly's model expects it**, not only as the proxy last reported it.
  Text Protly itself inserted since the last observed context (a space, a commit difference, a newline) is part
  of the expected start. Reason: the first key of a word can read a context that is still missing the previous
  commit and space (`enter-clears-web.md` 180-186).
- `after`: `documentContextAfterInput` at the word's first key.
- `history`: every state of the word Protly wrote, **including the intermediate state after the deletes and
  before the insert** (for example ㄱ to 가 passes through the empty word).
- `lastOwnEdit`: the time of Protly's last write, for a short own-edit window (start with 300 ms;
  `edit-menu-missing.md` F1 note).

Required behaviour, each a test (failing first):
- composing, context is `start + written`, after unchanged, no selection: keep.
- composing, `selectedText` non-empty: abandon (the H3 bug in `edit-menu-missing.md` 1.3: today a double-tap on
  the word just typed keeps it composing, and the next key writes the old word over the selection).
- **composing, `after` changed: abandon.** A tap inside the word (between 안 and 녕 of 안녕) gives a context of
  `start + 안`, which matches a history state, but the after-context is now `녕`. Test: history 안, 안ㄴ, 안녀,
  안녕; context `start + 안`, after `녕` -> abandon. Without this rule, the next backspace deletes 안 and the field
  shows 녀녕.
- composing, context changed in any other way (field cleared after a send, cursor moved elsewhere) and outside
  the own-edit window: abandon.
- **`hasText` is not used.** WebKit reports `hasText` false right after each edit (`enter-clears-web.md` 117);
  with plain text that would split words in Safari and Chrome. A cleared field already fails the context rule.
  Test: `hasText` false, context `start + written` -> keep. Sprint 4 item 1 (the comment at
  `KeyboardViewController.swift:159`) was about marked text and no longer applies; say so in the comment.
- **a context that lags behind Protly's own writes must not abandon.** Web views deliver the context late
  (`enter-clears-web.md` C1). Keep composing when the context matches `start + h` for any `h` in `history`, with
  the after-context unchanged. Tests: history 안, 안ㄴ, 안녀; context `start + 안ㄴ` -> keep. `start` "hello",
  Protly then inserted " " and a first key read the stale context "hello" -> keep. Context "" with an expected
  non-empty field: keep inside the own-edit window, abandon after it.
- compare tails, not whole strings: the proxy may truncate the context at the front, so a long field must not
  abandon. Test with a `start` of 500 characters truncated to its last 100.
- not composing, `lastTail` no longer a suffix of the context: forget last (unchanged behaviour).

### Task 1.3: the keyboard writes plain text

In `KeyboardViewController.swift`:
- `apply`: replace every `setMarkedText` and `unmarkText` with `PlainWord.edit` from the mirror (rename
  `marked` to `written`) to the new text: `textDocumentProxy.deleteBackward()` per deleted character, then one
  `textDocumentProxy.insertText`. Always the proxy's methods, never the controller's own `insertText` or
  `deleteBackward` overrides, which commit first and would recurse. Before any delete, run the FieldWatch
  check. Inside the own-edit window only the lag rules relax (trust Protly's model: the host applies proxy
  calls in order; only reading lags); the selection and after-context rules still apply. `.commit` writes only the difference (often nothing) and clears `written`. `.mark("")` becomes plain
  deletes; the settle-and-delete workaround for marked text goes.
- When FieldWatch abandons at a key, the key is not lost: `typeLetter` starts a fresh word with that letter
  (`TypingSession` has already taken it, so abandon first, then type it again into the fresh session), and
  `backspaceInWord` returns false so KeyboardKit deletes one character normally. Test the session side of this in
  ProtlyCore.
- `noticeFieldMoved`: call `FieldWatch.decide`; record the history it needs in `typeLetter` and `apply`.
- `viewWillDisappear`: the word is already plain text in the field; abandon still drops the session state. Update
  the comment.
- `textDidChangeAsync`: the composing guard existed because the context excluded marked text. Decide from the
  code whether it is still needed (autocap is off) and say which in the report.
- Return, space and punctuation keep going through `insertText`, which commits first. With plain text a Return
  after a word sends only the commit difference (usually none) and `"\n"`, which is what Apple's keyboard sends.
- Every comment that talks about the mark or marked text is updated.

Extend `KeyboardSourceRulesTests.swift`:
- fail if `setMarkedText` or `unmarkText` appears anywhere in `ios-app/Sources/ProtlyKeyboard`;
- fail if the bodies of `textDidChange`, `selectionDidChange` or `refreshField` call `insertText`,
  `deleteBackward` or `adjustTextPosition` on the proxy (host callbacks never write; `edit-menu-missing.md` 4.2).

### Task 1.4: prove it in the simulator, record it

- Push with `[shots]` in the commit message. The run must compile the keyboard and publish `STATUS measured`
  and layout `RESULT PASS`. Every phone check that passed on `main` before (`runs/e301e04-15/checks.txt` on
  `ci-shots`: 6.8-*, ws-*, 8.5-* without a key) must still pass. 8.5-9o is a known FAIL that Sprint 002 fixes; it
  may stay FAIL here. Sprint 4 item 12 (half word survives hide and reopen) should now pass trivially.
- Look at a bar-reading shot taken while a word is typed (`c-6.8-4-1-right.png` style): no underline under the
  word. Say so in the report with the file name.
- Add a short section "Plain-text composition (typing-fixes 001)" to `docs/ios-keyboard-notes.md`: what changed,
  the run folder, and the phone checks the tower still owes (below).

**Sprint 001 done when:** `swift test` and `npm test` pass; the source rule finds no marked text; the last
`[shots]` run publishes `STATUS measured`, layout `RESULT PASS`, and no check that passed on `main` fails.

Tower checks (phone): the owner types in Instagram DM (dark), Messages, KakaoTalk, Safari and Chrome: no
underline, the word is always visible; Return after a word with no space keeps the message in Safari and
Chrome; double-tap or long-press on the last word shows Copy; a flip from the bar after a word still works; hide
and reopen the keyboard mid-word, then keep typing.

## Sprint 002: Spanish words do not flip to Hangul

Files: `ios-app/ProtlyCore/Sources/ProtlyCore/LanguageDetector.swift`,
`ios-app/ProtlyCore/Tests/ProtlyCoreTests/LanguageDetectorTests.swift`. No run budget: ProtlyCore only.

### Task 2.1: the guard test first

Add tests that pin Korean after English, which today's suite would not notice breaking
(`spanish-flip.md`, Recommendation): `gym 가는중` and `테니스를` typed after an English word stay Korean. They
pass before any change.

### Task 2.2: option 2

Implement option 2 of `spanish-flip.md` exactly as described there: in rule 3, on commit only (`complete ==
true`), a word unknown in both lists whose composition is at least one syllable followed by a trailing run of
lone jamo that is not glue (ㅋ ㅎ ㅠ ㅜ, `ChatShorthand.glueJamo`) is English. Tests first, from that section:
the two failing reproduction tests in `spanish-flip.md` "Reproduction", the `endsInStrayConsonant` cases
(둧뭇ㅁ, 촘볃ㅅㅁ true; 했ㅋㅋ, 앜ㅋ, ㄱㅅ, 안녕 false). No existing test changes. Do not do the optional
second step (lone-consonant words follow the prior). Update rule 3 in the `LanguageDetector.swift` header
comment.

### Task 2.3: numbers

If the repo's `protly-eval` (or the measurement the research used) runs offline, re-run it and put the before and
after numbers in the PR body. Do not edit `docs/ios-keyboard-notes.md` in this sprint (Sprint 001 owns it this
wave); the tower records the numbers.

**Sprint 002 done when:** `swift test` and `npm test` pass with the new tests, and no existing test changed.

Tower check: on the phone, after an English word, type `me encanta el color` and confirm it stays Latin and
the center slot offers Polish (8.5-9o).

## Sprint 003: space bar cursor control

Depends on Sprint 001 (the same controller file, and the drag snapshot is simpler without marked text). Files:
`ios-app/ProtlyCore/**`, `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`,
`ios-app/Sources/ProtlyKeyboard/ProtlyActionHandler.swift`, `docs/ios-keyboard-notes.md`. Run budget: 4
`[shots]` runs.

### Task 3.1: `SpaceTrackpad` in ProtlyCore

A value type with `mutating func move(dx: Double, dt: Double) -> Int` (a UTF-16 offset for
`adjustTextPosition`) over a snapshot of the text before and after the cursor taken at drag start. Rules from
`space-trackpad.md` R4: cost per grapheme by width (6 pt narrow, 12 pt for Hangul, CJK and emoji); the
remainder carries between events; gain 1x below 100 pt/s rising linearly to 3x at 600 pt/s; offsets in UTF-16
units of whole graphemes; clamp at the ends of the snapshot. Horizontal only: vertical movement (R6) is out of
scope.

Tests, failing first: the horizontal ones listed in `space-trackpad.md` section 5 "Unit tests"
(`testSlowDragMovesOneNarrowCharacterPerSixPoints` through `testVerticalDriftKeepsHorizontal`). Drop
`testMarkedWordIsInTheSnapshot`: after Sprint 001 there is no marked word; replace it with a test where the word
being typed is plain text at the end of `before`.

### Task 3.2: wire it in

- R1: in `viewDidLoad`, `services.spaceDragGestureHandler.verticalThreshold = .greatestFiniteMagnitude` (or
  the equivalent if R4 makes KeyboardKit's handler unused; say which in the report). A thumb drifting up must
  never freeze the cursor.
- R4: override the open `handleDrag(on:from:to:)` in `ProtlyActionHandler` for `.space` while
  `keyboardContext.isSpaceDragGestureActive`. On the first event, commit the word being typed first (the commit
  can change its reading), then build the snapshot from Protly's model (the context minus `written`, plus the
  commit text, and the after-context), not from a fresh proxy read, which may lag. Also call `session.forgetLast()`
  and `endUndo()` at drag start, as the controller's `adjustTextPosition` override does, so a flip or Undo right
  after a drag cannot act on a stale context. Call `SpaceTrackpad` and move
  with `textDocumentProxy.adjustTextPosition`. Other actions keep KeyboardKit's behaviour.
- R3: a 0.4 s long-press delay for the space key only (`space-trackpad.md` R3 shows where), other keys keep
  0.5 s.
- R5 only if the run shows the drag lags; otherwise list it as not needed.

### Task 3.3: prove it

- A `[shots]` run must compile and keep every check that passed before passing.
- If XCUITest can press and drag on the space key by coordinate in the existing harness
  (`ios-app/CI/UITests/Driver.swift`), say so in the report; the drag scenario itself is Sprint 004's.
- Add a short section "Space trackpad (typing-fixes 003)" to `docs/ios-keyboard-notes.md` with the values used.

**Sprint 003 done when:** `swift test` and `npm test` pass; the last `[shots]` run publishes `STATUS measured`,
layout `RESULT PASS` and no regression.

Tower checks (phone, `space-trackpad.md` P3 to P5): drag left across the keyboard while the thumb rises, the
cursor never stops; slow drags are precise, a flick reaches about 40 characters; Korean and English feel equally
fast; `안녕` with no space, hold space, one step left gives `안|녕` with nothing lost.

## Sprint 004: simulator proof for all four

Depends on Sprints 001 and 003. Shares `ios-app/CI/**` and the workflow with Sprint 002 of the sim-phone-checks
campaign; the tower does not fly both at once. Files: `ios-app/CI/**`, `.github/workflows/keyboard-shots.yml`,
`docs/ios-keyboard-notes.md`. Run budget: 8 `[shots]` runs, the first one a probe.

### Task 4.1: host screens

The CI host (`ios-app/CI/Host/HostApp.swift`) gains screens chosen by a launch argument, all offline:
- **web composer** (`enter-clears-web.md` "Simulator scenario"): a bundled page with a plain `<textarea>`, an
  `<input>` in a `<form>` whose submit is logged and prevented, and a `contenteditable` "Enter to send" composer
  with the common `isComposing || keyCode === 229` guard. An event logger posts each DOM event through
  `window.webkit.messageHandlers` to the host, which writes `web-events.txt` into the run folder. A label shows
  the sent list for XCUITest. The page is dark (`color-scheme: dark`, black background,
  `caret-color: transparent` on the composer) so the same screen also checks visibility on a dark web page.

### Task 4.2: checks

New `CHECK` IDs, one line each in `checks.txt`, with `checks.py` rules unit-tested:
- `dark-1`: in the web composer, type `dkssud` with no space; the word's glyph ink while typing equals its ink
  after a space, and there are no underline pixels. (No "before" case: Sprint 001 has already removed marked
  text.)
- `ret-<step>-<field>`, steps 1 to 5 and fields `textarea`, `input`, `composer` (15 lines): the five steps of
  `enter-clears-web.md` (`안녕` then Return at once; `hello 안녕` then Return; the same with a space; with a 300 ms
  pause; one-word `ㅇㅋ`). The field text or sent list is exact. `web-events.txt` is published.
- `menu-0`, `menu-1`, `menu-4`: S0, S1 and S4 of `edit-menu-missing.md` 4.3, in the UIKit host. S0 is the
  control on Apple's keyboard; if it fails, fix the harness first.
- `pad-1..3`: if XCUITest can press and drag on space: a 1 s press then a drag left (cursor moves), a drag with
  the finger rising 80 pt (cursor keeps moving), and `안녕` then one step left (`안|녕`, read from the field's
  selection). If it cannot, record SKIP with the reason.

### Task 4.3: report

Extend the table in `docs/ios-keyboard-notes.md` with the new rows and timings. A FAIL caused by the keyboard is
reported, not fixed, and the tower plans the fix.

**Sprint 004 done when:** the last `[shots]` run publishes `STATUS measured` and layout `RESULT PASS`; every ID
above has a CHECK line; the verify command passes; at most 8 runs.

## Waves

| Wave | Sprints | Why |
|---|---|---|
| 1 | 001, 002 | disjoint files (002 touches only `LanguageDetector.swift` and its tests) |
| 2 | 003 | after 001 lands: same controller file |
| 3 | 004 | after 001 and 003; not while sim-phone-checks 002 flies (shared CI files) |

## Out of scope

- App settings and a settings screen (`docs/research/2026-10-30-app-settings.md`): read later, planned separately.
- The UI and UX audit and competitor ideas (`2026-10-30-ui-audit.md`, `2026-10-30-competitors.md`): Sprint 9.
- Vertical cursor movement (space R6) and the trackpad haptic (R2).
- Spanish option 3 (a Spanish word list).
