# Keyboard and App UI Implementation Plan

> **For Claude:** local campaign (owner choice 2026-10-30). The tower session on the laptop implements each sprint
> with subagents, one branch per sprint (a git worktree each for the two Wave 1 sprints), reviews and lands it.

**Goal:** Make the parts of the Protly keyboard people touch many times a message feel finished (the bar, the
protly key, the wait for a result and the result itself), and give the container app one guide screen that gets a
new user to a working Translate on the first try.

**Architecture:** Three sprints, one per part of the approved design. Sprint 001 redraws the bar and the protly
key; every decision behind a label (which action, which target, which symbol, whether a flip is a real word) moves
into ProtlyCore as pure functions with unit tests, and the SwiftUI views only draw them. Sprint 002 rewrites the
container app's single screen (`ProtlyApp.swift`, which does not link ProtlyCore). Sprint 003 switches the
Messages API call to streaming: a pure server-sent-events parser and a partial-JSON reader in ProtlyCore feed a
result card in the keyboard, and a compile-time stub client lets the simulator CI show every card state offline.

**Tech Stack:** Swift (ProtlyCore package, `swift test` on Linux), SwiftUI in the keyboard target (KeyboardKit
9.9.1 vendored) and the container app, the Anthropic Messages API (streaming), XCUITest and the keyboard-shots
workflow on `macos-26`, Python for `measure.py` and `checks.py`.

**Source of truth:** this file for the keyboard and app UI work (Sprint 9 of the keyboard). The why behind every
item is in `docs/plans/2026-10-30-keyboard-ui-design.md` (decisions D1 to D6; issue IDs B*, K*, P*, F*, A* from
`docs/research/2026-10-30-ui-audit.md`). Read the design's part for your sprint before the tasks here; this plan
does not repeat its reasons. `docs/plans/2026-10-28-ios-keyboard.md` stays the plan of record for keyboard
features, `docs/plans/2026-10-30-sim-phone-checks.md` for the simulator check harness, and
`docs/ios-keyboard-notes.md` records phone and simulator findings.

---

## Background for each sprint

- Read the repo `CLAUDE.md`, then the design doc's part for your sprint, then `docs/ios-keyboard-notes.md`
  (at least "Simulator phone checks" and "Plain-text composition (typing-fixes 001)").
- **Swift runs here, Xcode does not.** Write the tests first, then the code. Run
  `swift test --package-path ios-app/ProtlyCore` and `npm test` before every commit (CLAUDE.md); grep the output for
  "Executed N tests" (the tail shows swift-testing's "0 tests"). There is no simulator: the keyboard target is
  proved only by `[shots]`. Sprint 002 runs `xtool dev build` itself. `ios-app/Sources/ProtlyKeyboard/Secrets.swift`
  holds the real key here: never open, print or commit it.
- **The keyboard target does not build on Linux** (UIKit, KeyboardKit). It is compiled by the keyboard-shots
  workflow on macOS. A push to any branch other than `main` whose head commit message contains `[shots]` runs it,
  but only when the push touches `ios-app/**` or the workflow (the workflow's `paths` filter): an empty commit
  never runs it. The result is published to the orphan branch `ci-shots` under `runs/<sha7>-<run>/`. Read it with
  `git fetch origin ci-shots` and `git show origin/ci-shots:runs/<dir>/report.txt` (and `checks.txt`,
  `build.log`, `tree-*.txt` if present, PNGs with the Read tool). Each sprint has a run budget; build-fix runs
  count. Wait for a run to publish before pushing the next `[shots]` commit (a new one cancels the running one).
- **Known CI flake:** a single `band-*` layout check failing by exactly +17 pt (for example 69 instead of 52),
  together with a top-edge range of 17 pt, with the keys in place, counts as layout PASS (runs `b390712-8`,
  `307483a-12`, `28108ea-24`, `e014ba8-38`). If a run fails for a reason unrelated to your change (a simulator
  boot or XCTest harness failure), it may be re-run once with `gh workflow run keyboard-shots.yml --ref <branch>`,
  and that re-run does not count against the budget. Say so in the PR.
- **Who owns the CI files.** Sprint 002 of the sim-phone-checks campaign (PR #17, branch
  `opus/hopeful-archimedes-uk7tza`) owns `ios-app/CI/**` and the workflow while it flies. It turns on Full Access
  in the simulator (`test0_access`), adds real network checks with a CI-only key (`ios-app/CI/UITests/NetworkChecks.swift`)
  and drives the container app. Sprint 004 of the typing-fixes campaign comes after it and owns the same files.
  This campaign edits CI only where a sprint below says so.
- Put logic in ProtlyCore wherever possible, as pure functions or value types, so it is unit tested on Linux. Keep
  the SwiftUI views thin: they read published state and call the controller.
- Never break the phone build: do not edit `ios-app/Package.swift`, `ios-app/xtool.yml` or anything under
  `ios-app/Vendor/`. No `#if targetEnvironment(simulator)` paths in `ios-app/Sources/**` (Sprint 003's
  `PROTLY_CI_STUB` compilation condition is the one approved exception, set only in `ios-app/CI/project.yml`).
- `KeyboardSourceRulesTests.swift` reads the keyboard and app sources as text and enforces rules about them (no
  logging, the key only in the request, the clipboard read only in `readClipboard`, `UserDefaults` keys, the
  `@AppStorage(AboutMeLink.defaultsKey)` line in the app, `insertResult` called only by the panel's button,
  haptics off). Keep it passing; change a rule only where a sprint says so.
- Brand colors (design D3): paper `#F5F0E6`, ink `#1A1F2E` (`src/ui/tokens.css.js`). Dark mode: a paper pill with
  ink text. Light mode: an ink pill with paper text. Keys, key sizes and the keyboard background stay Apple's (D2).
- No haptics, no settings, no VoiceOver work (D6). Haptics stay forced off in `viewDidLoad`. One exception: the
  protly key's `accessibilityLabel` (Task 1.4). Reduce Motion is in scope: every animation below names its Reduce
  Motion form (`@Environment(\.accessibilityReduceMotion)`).
- Icons are SF Symbols, never Unicode glyphs: `sparkles` (Translate, Polish), `doc.on.clipboard` (Read),
  `arrow.uturn.backward` (Undo), `lock.fill` (Full Access off), `xmark` (cancel on the strip).
- **Design skill.** Tasks 1.3, 1.4, 2.1 to 2.4, 3.4 and 3.5 load the project skill `impeccable`
  (`.claude/skills/impeccable/`). Do not run its `scripts/impeccable` launcher (it downloads a binary); read
  `SKILL.md` and then `reference/ios.md`, `reference/craft-floor.md`, `reference/clarify.md`, plus
  `reference/onboard.md` for Sprint 002 and `reference/animate.md` and `reference/harden.md` for Tasks 1.3 and 3.4.
  There is no PRODUCT.md or DESIGN.md; the design doc is the brief.
- **Swift skills.** Tasks 1.3, 1.4, 2.1 to 2.4 and 3.4 end with a review pass using the project skill
  `swiftui-pro` (`.claude/skills/swiftui-pro/`, the references for views, data, design, accessibility and
  performance) before the first `[shots]` run (for Sprint 002, before `xtool dev build`). Tasks 3.1
  to 3.5 load `swift-concurrency` (`.claude/skills/swift-concurrency/`: async-sequences, tasks,
  memory-management, sendable, testing). Its project facts: ProtlyCore builds in Swift 6 mode with complete
  checking and no default isolation; the keyboard target builds in Swift 5 mode with minimal checking, so a
  Sendable or isolation mistake there is never reported. That is one more reason to put async logic in ProtlyCore.
  The deployment target is iOS 17: anything newer goes under `if #available`.
- Do not add packages (no AsyncAlgorithms, no ConcurrencyExtras): adding one means editing `Package.swift`, and
  the tests run offline.

## Sprint 001: bar and protly key

Design: Part 1. Files: `ios-app/ProtlyCore/**`, `ios-app/Sources/ProtlyKeyboard/ProtlyBar.swift`,
`ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`, `ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift`,
new `ios-app/Sources/ProtlyKeyboard/Brand.swift` and `ios-app/Sources/ProtlyKeyboard/BarSlotStyle.swift`,
`docs/ios-keyboard-notes.md`, and the CI lines listed in Task 1.5 only. Run budget: 4 `[shots]` runs.

**Order:** Tasks 1.1 to 1.4 start at once, with plain pushes (no `[shots]` in any commit message). Before the first
`[shots]` run, check that sim-phone-checks Sprint 002 (PR #17) has landed on main (`gh pr view 17 --json state`).
Only then do Task 1.5.

### Task 1.1: `BarAction` in ProtlyCore (what the center slot and the protly key show)

**Files:**
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/BarAction.swift`
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/Endonyms.swift` (`extension Languages`)
- Test: `ios-app/ProtlyCore/Tests/ProtlyCoreTests/BarActionTests.swift`

Today `ProtlyBar.center` (`ProtlyBar.swift:43-52`) picks `Undo`, then `Translate` / `Polish` from
`mode.draftMode`, then `Read clipboard`; the protly key (`KeyboardViewController.swift:495-500`, `act(nil)` at
`:243`) runs the field's action or reads the clipboard, and never undoes.

**Step 1: tests first.** `BarAction` is an `Equatable`, `Sendable` enum `translate(target: String)`,
`polish(korean: Bool)`, `read`, `undo`, with `symbol` (an SF Symbol name), `arrow` (true only for translate),
`title` (words only) and `spokenLabel` (for the protly key's `accessibilityLabel`). The view draws symbol, arrow
and title as separate views, so a right-to-left endonym cannot reorder them.

| Field text (or state) | center | `symbol` / `arrow` / `title` | `spokenLabel` |
|---|---|---|---|
| canUndo (any text) | `.undo` | `arrow.uturn.backward` / no / `Undo` | `Undo` |
| `오늘 고마워` | `.translate("English")` | `sparkles` / yes / `English` | `Translate to English` |
| `ru: 누나 고마워` | `.translate("Русский")` | `sparkles` / yes / `Русский` | `Translate to Русский` |
| `ok: 내일 봐` (not a listed code) | `.translate("English")` | `sparkles` / yes / `English` | `Translate to English` |
| `hello there` | `.polish(korean: false)` | `sparkles` / no / `Polish` | `Polish` |
| `ko: 낼 봐` | `.polish(korean: true)` | `sparkles` / no / `한 Polish` | `Polish Korean` |
| empty or whitespace, clipboard new | `.read` | `doc.on.clipboard` / no / `Read` | `Read clipboard` |
| empty or whitespace, clipboard not new | nil | (empty slot) | |

- `static func center(text: String, canUndo: Bool, clipboardIsNew: Bool) -> BarAction?` uses
  `ActionAPI.mode(forDraft:)` and `Languages.prefix(of:)` exactly as `ActionAPI.userMessage` does
  (`ActionAPI.swift:167-178`), so the label always names the target the request will use. Test that agreement:
  for each translate row, `userMessage(mode:text:)` contains `TARGET: <the English name>` for the same code (the
  polish, read and undo rows send no `TARGET:`).
- `static func protlyKey(text:canUndo:clipboardIsNew:) -> BarAction`: the same as `center`, except that where
  `center` is nil it is `.read` (the key reads the clipboard on an empty field, as `act(nil)` does today).
- The words a check reads are the title: test that `title` never contains `→` or any of `✦ ⧉ ↶`.

**Step 2: the endonym table.** `Languages.endonym(of code: String) -> String?`, in its own file `Endonyms.swift`,
never in `Languages.swift`: `tests/ios-app.test.js:33` runs `\("([a-z]{2,3})", "([^"]+)"\)` over the whole of
`Languages.swift` and compares the pairs with the extension's `LANG_NAMES`, so a second tuple table there breaks
`npm test`. Every code in
`names` has an endonym, capitalized as a label (`ru` Русский, `es` Español, `ja` 日本語, `en` English, `ko` 한국어).
Test: every code covered, none empty. The request keeps the English name (`TARGET:` is unchanged).

**Step 3:** implement, run `swift test`. Commit: `feat(core): BarAction and language endonyms for the bar`.

### Task 1.2: the left slot dims an unlikely flip (B4)

**Files:**
- Modify: `ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift` (or `LanguageDetector.swift`, whichever
  owns the word lists more naturally; say which in the report)
- Test: a new `FlipPlausibilityTests.swift`

`TypingSession.alternative` (`TypingSession.swift:39-42`) is the other reading. Add `alternativeIsWord: Bool`:
true when that reading is in the other language's bundled list (`en_50k.txt` keyed lowercased, `ko_50k.txt` as
`LanguageDetector` keys it; use `WordList.frequency(of:) > 0`), false otherwise, and true when there is no detector
yet (the lists load late: never dim on missing data). Learned words do not count (the design names the lists only).
While a word is still being typed the alternative is half a word, so it would dim on every keystroke: while
composing, count it as a word when some list entry starts with it (`hasPrefix`, as `decide(complete: false)` does).

Tests, failing first: `dkssud` typed as English -> the alternative `안녕` is a word; `rkskek` -> `가나다`
(not in `ko_50k`) dims; the keys of `hello` read as Korean -> the alternative `hello` is a word; a
mixed-case English alternative is looked up lowercased; a half-typed `dkss` (composing) is not dimmed; no
detector -> true; no alternative -> false.

Commit: `feat(core): alternativeIsWord for the flip slot`.

### Task 1.3: the bar view (B1, B2, B3, B5, B8)

**Files:**
- Modify: `ios-app/Sources/ProtlyKeyboard/ProtlyBar.swift` (all of it)
- Modify: `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift:7-22` (`ProtlyMode`), `:372-390`
  (`refreshField`), `:392-398` (`refreshMode`)
- Modify, only if the band split needs it: `ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift:6-21` (`ProtlyGeometry`)

1. `ProtlyMode` publishes `center: BarAction?`, `protlyKey: BarAction`, `alternativeIsWord: Bool` and
   `fullAccess: Bool` (from `hasFullAccess`), set in `refreshField` / `refreshMode` from Task 1.1 and 1.2.
   Drop `draftMode`: its last reader, `act()` at `KeyboardViewController.swift:260`
   (`requested ?? mode.draftMode ?? .in`), reads the mode from `mode.protlyKey` instead.
2. **The action stays visible while a word is typed.** `refreshField` today sets the draft mode to nil while
   `session.isComposing` (`KeyboardViewController.swift:375-376`). Since typing-fixes 001 the word being typed is
   plain text inside the context, so compute `center` from the context in every state. The clipboard rule
   (offered only on an empty field) stays as it is.
3. **Full-slot targets (B1).** Each of the three slots is a `Button`. One `BarSlotStyle: ButtonStyle`
   (`BarSlotStyle.swift`) does the full-slot part in `makeBody`:
   `.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)` plus the pressed highlight (item 9).
   Apply `.buttonStyle(BarSlotStyle())` once on the bar's `HStack`. The pill's own `padding` and `.capsule`
   background come before that full frame, or the pill fills the whole slot. The bar covers the whole band
   above row 1, `ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight` (46.5 pt), not only the 29 pt text row:
   replace `.frame(height: toolbarHeight).padding(.top, topBand)` (`ProtlyBar.swift:24-25`) with one frame of the
   full band height. The keyboard's total height (`ProtlyHeight.portrait`) and the rows must not move.
4. **Text where Apple's is (B8).** Text centers 22 pt below the glass top (today 32 pt; audit B8): the label sits
   in a `.frame(height: 44)` inside `.frame(maxHeight: .infinity, alignment: .top)`, with no padding derived from
   font metrics. If you change `topBand` or `toolbarHeight` instead, keep their sum, and say so (Task 1.5 may then
   need a `measure.py` change).
5. **Dividers (B8).** Thin vertical dividers between slots like Apple's (about 0.5 pt, `.separator` color, inset
   from the band's top and bottom), hidden next to an empty slot with `.opacity(0)`, not `if`, so the slots keep
   their identity.
6. **Left slot (B4).** `alt` without the curly quotes (`ProtlyBar.swift:31`), `.primary` when
   `alternativeIsWord`, else `.secondary`.
7. **Center slot (B2, B3, B5).** A capsule pill in the D3 colors (dark: paper fill, ink text; light: ink fill,
   paper text) with `Image(systemName: symbol)`, an optional `Text("→")` and `Text(title)` as separate views in one
   `HStack`. The scheme comes from KeyboardKit's `context.colorScheme` (the `KeyboardContext` `ProtlyRoot` already
   holds), the same source the keys use, never `@Environment(\.colorScheme)`: a dark keyboard in a light app must
   not get an ink pill on dark glass. Text: `.lineLimit(1)`, `.minimumScaleFactor(0.8)`; the whole bar is capped
   with `.dynamicTypeSize(...DynamicTypeSize.xxLarge)`. Motion: the pill appears with opacity and
   `scale(0.9)` over about 0.15 s ease-out and leaves with opacity only over about 0.1 s (an asymmetric
   transition); a change between two actions (Translate to Polish) only crossfades the label, with no scale.
   Under Reduce Motion every change is opacity only. SwiftUI wiring: put `.animation(_:value: mode.center)` on the
   always-present `ZStack { Color.clear; center }`, not on the pill (an `if let` removal takes the modifier with
   it, so there is no fade-out) and not on the `HStack` (the side slots would fade on every key). The pill's
   insertion and removal transition handles appear and leave; for the crossfade, the label inside the pill gets
   `.id(action)` with `.transition(.opacity)`, because a `.translate` to `.polish` change keeps the pill's identity
   and would not animate otherwise. Endonyms and titles are plain `String`s passed to `Text`'s String initializer,
   never `LocalizedStringKey`.
   **Colors:** a `Brand` enum in `Brand.swift` with `paper` and `ink` as sRGB `Color`s, written once as
   `static let paperHex = 0xF5F0E6` and `static let inkHex = 0x1A1F2E` (Task 3.6 adds a test that reads these lines),
   and `pillFill(_ scheme: ColorScheme)` / `pillText(_:)`.
8. **Right slot.** Unchanged behaviour (one fix or completion), now a full-slot button too.
9. **Pressed state.** `BarSlotStyle` for every slot: while `configuration.isPressed`, a rounded `systemFill`
   highlight behind the slot, as Apple's bar does; the label is not dimmed. Use
   `.background(configuration.isPressed ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))`,
   one view whose style changes, not an `if`. No haptics.
10. Keep the `ZStack { Color.clear; ... }` reason (`ProtlyBar.swift:16-17`): an empty slot still takes its third.

Commit: `feat(keyboard): full-slot bar with the action pill and dividers`.

### Task 1.4: protly key and Full Access off (K1, F1)

**Files:** `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift` (`act` at `:243-280`, `setKeyboardType` at
`:495-500`, `ProtlyRoot.buttonContent` at `:533-541`), `ios-app/Sources/ProtlyKeyboard/ProtlyBar.swift`.

1. **Protly key (K1).** Its content (`Image(systemName: "character.bubble")` today) becomes
   `Image(systemName: mode.protlyKey.symbol)` in the same accent as the pill (tint only: Apple's key shape, size
   and pressed look stay), with `.accessibilityLabel(mode.protlyKey.spokenLabel)` (the D6 exception; today
   VoiceOver reads "Keyboard Type - emojis"). The key is a KeyboardKit gesture button, not a SwiftUI `Button`: set
   the accent in the existing `keyboardButtonStyle(builder:)` (`KeyboardViewController.swift:576`), for example
   `if case .keyboardType(.emojis) = params.action { style.foregroundColor = Brand.pillFill(context.colorScheme) }`,
   and leave `params.isPressed` to KeyboardKit. Do not wrap the key in a `Button` or a `ButtonStyle`. A tap runs
   exactly what the symbol says: `.undo` calls `undoInsert()`, every other value calls `act(nil)` as today. Symbol
   and action come from the same `BarAction` value, so they cannot disagree.
2. **Full Access off (F1, keyboard side).** When `fullAccess` is false the pill is an outlined capsule: a 1 pt
   rule in the label color, no fill, label-colored text, `lock.fill` in front of the title. Not an opacity-dimmed
   fill (that measures about 2.5:1 on the light-mode ink pill, and the pill stays tappable). A tap on it, or on
   the protly key, shows one line that says why, with Done, instead of a failed call: reuse `PanelState.notice`
   with `Translate, Polish and Read need Full Access: Settings > General > Keyboard > Keyboards > Protly > Allow Full Access`.
   Replace the `.failed(...)` at `KeyboardViewController.swift:251-253` with this notice.
3. Add a rule to `KeyboardSourceRulesTests.swift`: the bar and the protly key read their labels only through
   `BarAction`, so a label cannot drift from the request again. The check: no string literal that is exactly
   `"Translate"`, `"Polish"` or `"Read clipboard"` (regex `"(Translate|Polish|Read clipboard)"`) in any file
   `sources()` returns except `ProtlyApp.swift` (it returns both source folders). Longer strings such as the Full
   Access notice or `Panel.swift`'s `"Polishing"` stay allowed. Also: `ProtlyBar.swift` contains
   `accessibilityReduceMotion`.

Commit: `feat(keyboard): protly key follows the bar action; Full Access lock`.

### Task 1.5: CI catch-up and simulator proof

Only after sim-phone-checks Sprint 002 is on main.

1. `git fetch origin && git merge origin/main` (never rebase or force-push: the PR may already be open). Re-run
   `npm test`, `swift test` and the Python tests; push.
2. The CI edits this sprint may make, each in its own commit, nothing else under `ios-app/CI/**` and no workflow
   change:
   - `ios-app/CI/UITests/PhoneChecksUITests.swift`: the four center-slot lines in `checks85()` (today
     `expectSlot(it, "center", readSlot(.center, it), equals: "Translate")` / `equals: "Polish"`). They match
     the label's **words only**, not the symbols, which OCR may not read: 8.5-1o `Русский`, 8.5-6o `English`,
     8.5-7o and 8.5-9o `Polish`. If OCR returns the symbol or arrow too, use the closure form on the same line,
     for example `expectSlot(it, "center", readSlot(.center, it), q("Русский")) { $0.contains("Русский") }`.
   - `ios-app/CI/UITests/Reader.swift`: add `ru-RU` to `languages` (one line), so OCR can read `Русский`.
   - `ios-app/CI/UITests/NetworkChecks.swift` (added by sim-phone-checks 002): it compares the center label too
     (`tryAction`/`attempt` with `center: "Translate"` / `"Polish"`, the `label == want` comparison, and
     `center.text == "Read clipboard"`). Apply the same words-only change there and to nothing else in the file:
     `Translate` becomes `English` or the target's endonym, `Read clipboard` becomes `Read`, and the comparison
     becomes a contains-the-word match. The panel labels (`Translating`, `Insert`, `Retry`, `Cancel`, `Done`,
     `Save`) do not change in this sprint; leave them.
   - `ios-app/CI/measure.py` and `ios-app/CI/test_measure.py`: `bar-center-07` has a 2 pt tolerance
     (`measure.py:59`) and the `sparkles` symbol moves the OCR'd word about 10 pt, so plan this change, not "only
     if": measure the pill's center, not the word's. Check the other bar measurements (keyboard background sampled
     6 pt below the top edge; bar text detection) the same way. Say what changed and why.
3. Push with `[shots]` in the commit message. Read `report.txt`, `checks.txt` and the trees.
4. From the published accessibility trees (`tree-06-word-typed.txt` and `tree-07-*.txt`), list each slot's hit
   frame for each slot that shows a button (the right slot is empty in shots 06 and 07: a suggestion shows only
   while composing); each must be at least 120 x 40 pt. Look at shot 06 (`hello ` typed): the pill shows `sparkles` Polish. Shots
   02 to 05 (empty field) keep an empty center slot (B6 is out of scope). If Full Access was off in a run, the
   shots show the locked pill instead; say which.
5. Add a short section "Bar and protly key (keyboard-ui 001)" to `docs/ios-keyboard-notes.md`: what changed, the
   run folder, the hit frames, and the phone checks the tower still owes (below).

**Sprint 001 done when:** `swift test` and `npm test` pass; the last `[shots]` run, after the merge
above, publishes `STATUS measured`, layout `RESULT PASS` (flake rule above) and every phone check PASS (a network
check SKIP for the request cap is not a FAIL); the hit frame of each bar slot that shows a button is at least
120 x 40 pt; `KeyboardSourceRulesTests` checks that `ProtlyBar.swift` reads `accessibilityReduceMotion`; shot 06 shows the
pill; at most 4 runs.

Tower checks (phone): the feel of the bar and the pill (dark and light apps), a flip of a real word vs a dimmed
one, the protly key's symbol after a Replace (`arrow.uturn.backward`) and on an empty field (`doc.on.clipboard`),
Full Access off shows the outlined lock pill and the reason line, the pill in a dark keyboard field inside a light
app, and whether the pill is too loud (design D3).

## Sprint 002: app guide screen

Design: Part 2. Files: `ios-app/Sources/Protly/ProtlyApp.swift` only. The app does not link ProtlyCore, has no
test target, and must keep building with `xtool dev build` (run it on the laptop). Run budget: 1 `[shots]` run, after
sim-phone-checks 002 (PR #17) has landed and this branch has merged main, because the 7.7-* checks drive this
screen; the screen's own shots come in Sprint 003. `docs/ios-keyboard-notes.md` belongs to
Sprint 001 in this wave: put notes in the PR body instead.

**Keep, or the container-app checks of sim-phone-checks 002 break** (`NetworkChecks.swift` finds these by label):
the placeholders `Who you are, in a few facts` (About me) and `Type here` (test field), the counter text ending in
` / 1000`, the buttons `Copy for the keyboard` and `Copied`, `AboutMeLink` with its three constants
(`tests/about-me.test.js`), the line `@AppStorage(AboutMeLink.defaultsKey) private var aboutMe = ""`
(`KeyboardSourceRulesTests`), the `.onChange(of: aboutMe)` lines that count and cut by unicode scalars
(`tests/about-me.test.js:35-38`), the counter label exactly `N / 1000` with nothing before or after it
(`NetworkChecks.counter` is an anchored regex), and `copyForKeyboard()` unchanged (`ProtlyApp.swift:63-71`): the
button calls it as it is and then sets focus and the banner (Task 2.4). The icon
(`ios-app/Support/AppIcon.png`) stays.

TDD does not apply to this target (no tests run against it). The guards are the existing tests above; run
`npm test` after every task.

### Task 2.1: theme and the scrolling screen

Replace the `NavigationStack { Form { ... } }` (`ProtlyApp.swift:28-60`) with one `ScrollView` of sections in
the D3 colors: paper background and ink text in light mode, reversed in dark mode (`@Environment(\.colorScheme)`;
set the background explicitly, do not rely on the system). Section titles use `.fontDesign(.monospaced)` (no
bundled font). No paged onboarding (D5). Contrast: never system `.secondary` on paper (3.3:1); secondary text and
placeholders use ink at 70% opacity or more (5.7:1), and in dark mode paper at 60% or more on ink (6.0:1). One
`.tint` on the whole screen, ink in light mode and paper in dark mode, so no control is system blue. Text fields
(About me, the test field) get a visible 1 pt rule in the secondary color. Hint lines embed the keyboard's SF
Symbols with `Text("Tap \(Image(systemName: "sparkles")) Polish")`. Colors come from a small `Brand` enum inside
`ProtlyApp.swift` (the app does not link the keyboard's), with the same `paperHex = 0xF5F0E6` and
`inkHex = 0x1A1F2E` lines as Task 1.3; the background is `.background { Brand.paper(scheme).ignoresSafeArea() }`.
Commit after each task.

### Task 2.2: hero and "Turn on Protly" (F2)

1. Hero: `protly` and one line, "Write Korean, send English."
2. Two steps, each with a one-line reason: add the Protly keyboard; turn on Allow Full Access (Translate, Polish
   and Read need the network and the clipboard). An `Open Settings` button opens
   `UIApplication.openSettingsURLString` through `@Environment(\.openURL)`:
   `Button("Open Settings", systemImage: "gear", action: openSettings)` with
   `if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }`, no force unwrap. The app cannot
   read whether the keyboard or Full Access is on (no App Group): show no status.
3. "What Protly sends", right after the Full Access step (where iOS shows its warning), one paragraph: only when an
   action is tapped, the field text (or the copied text for Read) and the About me note go to the model API.
   Keystrokes are never sent; words the keyboard learns stay on this phone.

### Task 2.3: "Try it" (A1, A4)

The test field (placeholder `Type here`) moves up into this section.
1. First line, above the field: switch to Protly with the globe key under the keyboard, and back the same way.
2. Three chips (at least 44 pt tall; `ViewThatFits { HStack; VStack }`, iOS 17 has no wrapping stack) that put text in the field. A tap fills the field,
   focuses it (`@FocusState`) and shows one hint line under it. Headline first:
   1. Korean chip: puts `오늘 고마워` in the field; "Tap `sparkles` → English."
   2. Polish chip: puts a short English sentence with two or three mistakes in the field; "Tap `sparkles` Polish."
   3. `ru: 고마워` chip: puts `ru: 고마워` in the field; "Tap `sparkles` → Русский."
3. Below the chips, three numbered instruction rows (plain text, not buttons: they change nothing in the field):
   1. "Type dkssud, then tap the left slot."
   2. "Type teh, then tap the right slot."
   3. "After a Replace, tap `arrow.uturn.backward` Undo."

### Task 2.4: About me (A2)

1. About me keeps the field, the counter and `Copy for the keyboard` (see Keep). After the copy, focus the test
   field and show a numbered banner: 1. Tap `doc.on.clipboard` Read in the bar. 2. Allow Paste. 3. Save. Copying
   an empty note still clears it (say so in one line).

**Sprint 002 done when:** `npm test` passes; `swift test` (the source rules read `ProtlyApp.swift`) passes;
`xtool dev build` passes on the laptop; every label under Keep is still in the file; its one `[shots]` run has
every 7.7-* check PASS.

Tower checks (phone): Open Settings lands on Protly's own Settings page; each Try it chip does what its line says
with the Sprint 001 bar; the About me banner flow saves a note; dark and light mode.

## Sprint 003: streaming result card and CI

Design: Part 3. Depends on Sprints 001 and 002, and does not fly until typing-fixes Sprint 004 has landed (it owns
`ios-app/CI/**` and the workflow until then). Files: `ios-app/ProtlyCore/**`, `ios-app/Sources/ProtlyKeyboard/**`
(not `Secrets.swift`), `ios-app/CI/**`, `.github/workflows/keyboard-shots.yml`, `docs/ios-keyboard-notes.md`,
new `tests/brand.test.js`.
Run budget: 8 `[shots]` runs, the first one a probe.

### Task 3.1: SSE event parser in ProtlyCore

**Files:** Create `ios-app/ProtlyCore/Sources/ProtlyCore/ActionStream.swift`; Test `ActionStreamTests.swift`.

A value type fed raw bytes in any chunking (`mutating func feed(_ bytes: some Sequence<UInt8>) -> [Event]`). It
splits on line ends at the byte level (so a multi-byte UTF-8 character split across chunks is never decoded in
halves), reads `event:` and `data:` lines, ends an event at a blank line, and decodes `data` as JSON. Events kept:
`text(String)` from `content_block_delta` with `delta.type == "text_delta"`; `stop(String)` from
`message_delta.delta.stop_reason`; `error(type: String, body: Data)` from `event: error`. `thinking_delta`,
`signature_delta`, `ping`, `message_start`, `content_block_start/stop` and `message_stop` are read and dropped.
The shape (Anthropic streaming docs):

```
event: content_block_delta
data: {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "..."}}

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": null}}

event: error
data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}
```

Tests, failing first: a whole recorded stream (thinking block, then text block, then `end_turn`) in one chunk and
one byte at a time give the same events; `\r\n` line ends; a Korean character split across two chunks; thinking
deltas dropped; an `error` event; a `data:` line that is not JSON is skipped, not a crash.

`ActionStream` and `ActionStream.Event` are `public` and declare `Sendable` explicitly (public types are not
implicitly Sendable). The parser keeps its own byte buffer and only builds events when a line ends, so a caller
may feed it whole chunks; it must not allocate per byte. All tests here are synchronous.

### Task 3.2: the partial translation

**Files:** Create `ios-app/ProtlyCore/Sources/ProtlyCore/PartialTranslation.swift`; Test `PartialTranslationTests.swift`.

Given the model's text so far (the JSON object being built), return the decoded value of `"translation"` so far,
or nil before it starts. Handle every JSON escape, a `\uXXXX` escape cut across deltas (hold it back until
complete), surrogate pairs, a key order where `back_translation` comes first, and whitespace around the colon.
Never return a dangling backslash. Tests for each case, plus: the final full text gives the same string as
`ActionAPI.parse` would. `PartialTranslation` is `public` and explicitly `Sendable`; its tests are synchronous.

### Task 3.3: streaming request, result and client

**Files:** `ios-app/ProtlyCore/Sources/ProtlyCore/ActionAPI.swift`, new
`ios-app/ProtlyCore/Sources/ProtlyCore/ActionStreaming.swift`, `ios-app/Sources/ProtlyKeyboard/ActionClient.swift`,
tests in `ActionAPITests.swift` / `ActionRequestTests.swift` / `ActionAPIHostileTests.swift` and a new
`ActionStreamingTests.swift`.

**Where the code lives.** The stream driver (bytes in, bounded reader, `ActionStream`, `PartialTranslation`,
updates out) is ProtlyCore code, generic like `collect` (`<S: AsyncSequence>(_ bytes: S, ...) where S.Element == UInt8`; a
`Failure` constraint would need iOS 18), so Swift 6
checking covers it and it is tested on Linux. `ActionClient` keeps only `session.bytes(for:)`, the status branch
and the URL error mapping. The update type is
`public enum ActionUpdate: Sendable, Equatable { case partial(String), done(ActionResult), failed(ActionError) }`
(add `Equatable` to `ActionResult` and `ActionError` if missing).

1. `ActionAPI.body` adds `"stream": true`; every other field stays (update the body test).
2. Split `parse(status:body:)` (`ActionAPI.swift:194-213`): the part after the status check becomes
   `result(text: String, stopReason: String?) -> Result<ActionResult, ActionError>` (`refusal` -> `.refused`,
   `max_tokens` -> `.truncated`, else the JSON). The whole-body path and the stream both use it; existing tests
   keep passing unchanged.
3. Stream errors: map the `error` event's `error.type` to the HTTP status it stands for
   (`invalid_request_error` 400, `authentication_error` 401, `permission_error` 403, `not_found_error` 404,
   `request_too_large` 413, `rate_limit_error` 429, `api_error` 500, `overloaded_error` 529, unknown 500) and
   call today's `kind(status:body:)` with the event's data, so `.spendLimit` keeps working from its `details`.
4. A reply that is not 200 is a plain JSON error body: read it bounded (`collect`) and map with
   `kind(status:body:)` as today.
5. A bounded stream reader: `maxResponseBytes` (2 MB) counts the raw stream bytes, framing and thinking deltas
   included. Check: one `text_delta` event is about 112 bytes of framing plus its text, and the reply is at most
   16000 tokens (thinking included), so even one token per event is about 16000 x 120 = 1.9 MB. 2 MB holds; real
   deltas carry several tokens. Past the cap -> `.parse`, as today. Test with a synthetic stream just over the cap.
   **Timeouts stay in URLSession**, with today's values: `timeoutIntervalForRequest` (`idleTimeout`, 30 s) is the
   gap between bytes and `timeoutIntervalForResource` (`totalTimeout`, 90 s) the whole call; both already cancel
   `bytes(for:)` and throw `URLError.timedOut`. Add no `Task.sleep` timers and no task-group race. Fix the comment
   at `ActionAPI.swift:99-100` ("the API sends the reply whole" is no longer true: pings and thinking deltas reset
   the idle timer). 90 s now caps the whole streamed reply; a timeout after text is on screen follows Task 3.4
   step 5 (text kept).
6. `ActionClient.run` returns `AsyncStream<ActionUpdate>`: `partial` values, then exactly one `done` or `failed`.
   Build it so cancellation reaches the download:
   ```swift
   AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
       let producer = Task {
           defer { continuation.finish() }
           // bytes(for:), status branch, then the ProtlyCore driver yields into continuation
       }
       continuation.onTermination = { _ in producer.cancel() }
   }
   ```
   Without `onTermination`, cancelling the consumer only stops the iteration and the download goes on.
   `partial` always carries the whole translation so far, never a delta, so `.bufferingNewest(1)` drops nothing
   that matters and memory stays bounded while the main actor is busy (the default `.unbounded` would hold a copy
   of the text per update). The final `done` / `failed` is yielded last, so it is never the one dropped. The
   driver yields `partial` only when the string changed (thinking, ping and signature events change nothing).
   `ActionClient` stays nonisolated (never `@MainActor`), so the download and parsing run off the main actor; add
   a rule to `KeyboardSourceRulesTests` that `ActionClient.swift` contains no `@MainActor`.
   `testTheKeyGoesOnlyIntoTheRequest` must still pass.
7. **Cancellation is not a network error (bug today).** `ActionClient.swift:26-30` maps `CancellationError`
   (thrown by `collect`'s `checkCancellation`) and `URLError.cancelled` to `.network`. Today the controller hides
   it with `Task.isCancelled`; in a stream it would become a visible `failed(.network)`. Catch both and finish
   the stream with no element. Test it in ProtlyCore through the driver.
8. **Tests are deterministic**, XCTest like the other 23 files, no `Task.sleep` anywhere. Driver tests use a new
   scripted-chunk fake AsyncSequence in `ActionStreamingTests.swift` (the `Bytes` fake in `ActionCollectTests` is
   private and yields single bytes). Cancellation test: an
   endless fake sequence whose `next()` uses `withTaskCancellationHandler` to fulfil an expectation; cancel the
   consuming task and `await fulfillment(of:timeout:)`. That proves consumer cancel -> `onTermination` -> producer
   cancel. Never assert intermediate states by timing.

### Task 3.4: progress strip and result card

**Files:** `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift` (`act`, `run`, `insertResult`,
`closePanel`), `Panel.swift`, `ProtlyBar.swift`, `FieldText.swift`, new `ResultCard.swift`, `ProgressStrip.swift` and `ResultFeed.swift`
in the same folder. Do not move `ProtlyMode` or `ProtlyRoot`: `KeyboardSourceRulesTests` finds them in
`KeyboardViewController.swift` by name.

**State and rendering (do this first).**
- Streamed text never goes through `ProtlyMode`. Every `@Published` write re-runs `ProtlyRoot.body`, which
  rebuilds the keyboard layout and the button closures, so every key would redraw on every delta. Add
  `@MainActor @Observable final class ResultFeed { var partial = ""; var back = ""; var failed: ActionError? }`
  (Observation works on iOS 17 and in Swift 5 mode). The controller owns it and only `ResultCard` reads it.
  `mode.panel` changes once at the first text and once at the end.
- The consumer loop in `run` (today `KeyboardViewController.swift:305-317`):
  `for await update in stream { guard let self, !Task.isCancelled else { return }; ... }`, binding `self` weakly
  on every element. Never `guard let self` before the loop: that holds the controller for up to 90 s if it is
  torn down without `viewWillDisappear`. The cancellation check also stops a late partial from bringing the card
  back after `xmark` or after a Retry replaced the task.

The design's Flow, steps 1 to 6, in order:
1. A tap keeps the keys. The bar becomes a progress strip: a soft gradient glow in the D3 colors (the only
   gradient, only while a call runs), the mode and target (`Translating → English…`) and an `xmark` button with a hit area of
   at least 44 x 44 pt. A tap on the strip does nothing (B10). After 8 s a line naming the operation appears:
   `Still translating…`, `Still polishing…` or `Still reading…` (P5). The glow is a thin band along the strip's
   edge, never under the text (a paper glow under near-white text in dark mode keeps changing its contrast). It
   animates one gradient offset with no blur, and stops on done, cancel and `viewWillDisappear`. Under Reduce
   Motion the gradient is still. All of it lives in a `ProgressStrip` view: the glow runs on its own
   `@State private var phase` (`.phaseAnimator` or a `repeatForever` animation), never through `ProtlyMode` and
   never as a `Task` loop. The 8 s line is
   `.task(id: callID) { slow = false; do { try await Task.sleep(for: .seconds(8)) } catch { return }; slow = true }`,
   with a fresh `callID` per call (a Retry of the same action must restart it): the state
   changes only when the sleep finished, never after `try?`, and no second stored `Task` exists for `xmark` to forget.
2. At the first partial text, a glass card grows down from the strip over the keys (crossfade under Reduce
   Motion): header naming the target (`→ English`), the text arriving with a caret, and once done the back
   translation dimmed below it (P1, P2). Glass: `glassEffect(.regular, in: .rect(cornerRadius: 16))` inside
   `if #available(iOS 26, *)` in one `ViewModifier`, else `.background(.regularMaterial, in: .rect(cornerRadius: 16))`
   (the target is iOS 17); no hand-rolled blur. Caret: text, not an icon, and always steady (no blink, so no
   Reduce Motion branch): `let caret = Text("▍").foregroundStyle(.secondary)` and `Text("\(feed.partial)\(caret)")`
   (interpolation, not `Text + Text`). The card's buttons ignore taps for 0.5 s after the card appears, because
   the keys were live and a typing thumb is right there: store the time the card appeared (`systemUptime`, as
   `confirmNote(_, shownAt:)` does) and gate the buttons with `AboutMe.canSave(shownAt:now:)` itself (its
   `saveDelay` is 0.5 s); no new function.
3. Buttons at least 44 pt: `Copy` and `Replace` for Translate and Polish, `Copy` and `Insert` for Read (P3, P8).
   Copy writes the result to `UIPasteboard.general` in one `copyResult()`. `testTheClipboardStringIsReadOnlyInReadClipboard`
   cannot tell a read from a write, so amend it to allow exactly one assignment, inside `copyResult()`. After
   copying, store the pasteboard's `changeCount` under the clipboard key so the bar does not offer Read of
   Protly's own copy. Update `testInsertResultIsCalledOnlyByThePanelsInsertButton`
   to the new button wiring, keeping its intent (only the panel's button replaces text).
4. `xmark` or Cancel puts the cursor back where it was before `FieldText.read` moved it (P6):
   `FieldText.read` returns the offset it moved, and a new `FieldText.restore` moves it back, because the source
   rules allow `adjustTextPosition(byCharacterOffset` only in `FieldText.swift`. If the field text
   changed during the call, keep the result and offer only `Copy` (P10), instead of "The text changed".
5. Errors in plain words; `Retry` only for `.network`, `.timeout`, `.overloaded`, `.rate` (P4). Review
   `ActionError.message` as a copy table, one line per `ActionError.Kind`, each saying what happened and what to
   do next; change wording only where a line lacks the next step. Where the error shows:
   - **No text yet:** the error line replaces the strip's label (with Retry where it applies); the keys stay and
     no card opens.
   - **Text already on screen** (`.truncated`, `.refused`, or the connection drops mid-stream): keep the text
     shown, dimmed, add one error line under it, and offer only `Copy` (plus Retry where it applies). Never clear
     text the user has already seen.
6. Card text follows Dynamic Type (P7): text styles, not fixed sizes, capped with
   `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`. Long text scrolls inside the card; the buttons stay
   pinned below it: the text in a `ScrollView` with `.defaultScrollAnchor(.bottom)` (it follows new text without a
   `scrollTo` per delta), the buttons in `.safeAreaInset(edge: .bottom)` inside a `ViewThatFits` (one row, else
   stacked), each with `.frame(minHeight: 44).contentShape(.rect)` on its label. Fix the existing fixed sizes in
   `Panel.swift` while there (`.font(.system(size:))` at lines 32, 34, 47 and 81 become text styles) and the
   view-argument background at line 59 (`.background(RoundedRectangle(...).fill(Color(.secondarySystemBackground)))`
   becomes the glass modifier above).

### Task 3.5: CI stub and shots

1. **Stub client.** `ios-app/Sources/ProtlyKeyboard/StubActionClient.swift`, wholly inside `#if PROTLY_CI_STUB`,
   produces an `AsyncSequence` of recorded byte chunks with delays and feeds it to the same ProtlyCore driver as
   the real client, so cancel and `xmark` are exercised in CI (the 2 MB cap is unit-tested in Task 3.3). Delays are
   `try await Task.sleep(for:)` and let the error propagate, never `try?`, or a slow stub ignores `xmark`. Set the
   condition only on the `ProtlyCIKeyboard` target in `ios-app/CI/project.yml`
   (`SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) PROTLY_CI_STUB`); `ios-app/Package.swift` never defines it. The extension cannot read the
   host's launch arguments, and sim-phone-checks 002's network checks must keep calling the real API through the
   same CI keyboard, so the stub answers **only drafts that start with a fixed marker** (for example
   `protly-stub ok`, `protly-stub slow`, `protly-stub error`); every other draft goes to `ActionClient` as on the
   phone. It is checked before the API key, so it works with an empty key. Source rules: `PROTLY_CI_STUB`
   appears only in the stub file and its one call site.
2. **Shots** (the design's CI list): waiting, mid-stream, complete and error card, each in dark and light mode
   (P9); the bar shots in light mode too; a check that each bar slot's hit frame is at least 120 x 40 pt; the
   container app guide screen (Sprint 002) in dark and light mode; one bar shot at a large text size (`xxLarge`
   or above) with a long target name such as `ms:` (Bahasa Melayu) or an Arabic-script one, to catch overflow and
   bidi order; a waiting shot that shows the error-before-text strip and a card with text kept after an error;
   memory during a stream under the 40 MB budget; a CHECK that the error-after-text shot shows the kept text and
   the error line. Source rule: `ProgressStrip.swift` and `ResultCard.swift` contain `accessibilityReduceMotion`.
   New `CHECK` IDs get `checks.py` rules with unit tests.
3. **Panel names.** The `[probe]` panel probe in `PhoneChecksUITests.swift` and the network checks in
   `NetworkChecks.swift` wait for `Insert` / `Retry` / `Done` (Read), tap `Cancel`, and read `Translating` from the
   loading panel; update each to the new names (`Replace`, `Copy`, `Insert` for Read, `Retry`, the `xmark`
   button or the card's Cancel) and to the progress strip. Also fix the comment in
   `checks85()` that says the bar offers no action while a word is typed (no longer true since Sprint 001).

### Task 3.6: record

Add "Streaming result card (keyboard-ui 003)" to `docs/ios-keyboard-notes.md`: the run folder, the new checks, the
memory figure, and the phone checks the tower owes.

Also add `tests/brand.test.js` (both Sprint 001 and 002 have landed by now): it reads the `paperHex` and `inkHex`
lines from `ios-app/Sources/ProtlyKeyboard/Brand.swift` and `ios-app/Sources/Protly/ProtlyApp.swift` and checks
they equal paper and ink in `src/ui/tokens.css.js`, so the three copies of the brand cannot drift.

**Sprint 003 done when:** `swift test` covers the parser cases above and passes; `npm test` and the
Python tests pass; the last `[shots]` run publishes `STATUS measured`, layout `RESULT PASS` (flake rule above),
the new checks pass and every check that passed on main still passes; the card and app shots exist in both modes;
at most 8 runs.

Tower checks (phone): a real streamed Translate and Polish (first words on screen, then the back translation);
Cancel puts the cursor back; Replace and Copy; an error with Retry (airplane mode).

## Waves

| Wave | Sprints | Why |
|---|---|---|
| 1 | 001, 002 | disjoint files (002 touches only `ProtlyApp.swift`). 001's and 002's `[shots]` runs wait until sim-phone-checks 002 (PR #17) lands. 001's few CI lines may overlap typing-fixes 004 if both fly together: whichever lands second merges main and re-runs `[shots]`. |
| 2 | 003 | after 001 and 002 land, and only after typing-fixes 004 has landed (shared `ios-app/CI/**` and workflow). |

## Out of scope

- Register chips on the result (casual / polite / formal; 반말 / 해요체 / 합쇼체).
- A Korean gloss under a Polish result.
- Streaming in the Chrome extension, and any Chrome extension change (D1).
- Something in the empty-field center slot (B6).
- VoiceOver labels and announcements (K2); haptics, sound and settings (H1, A3, D6).
- Usage counts in the app and the App Group spike: the settings campaign.
