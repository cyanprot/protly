# Space bar cursor control: why it feels worse than Apple's

Research, 2026-10-30. Problem from daily use: holding the space bar and dragging to move the cursor (the
"trackpad") is still uncomfortable next to Apple's keyboard. Earlier phone checks already noted the symptoms:
"Space-drag cursor stutters (steps), Apple's glides continuously" (`docs/ios-keyboard-notes.md:136`) and "steps
stall between characters, no vertical movement" (`docs/ios-keyboard-notes.md:216`). Sprint 4's plan promised "a
smoother space drag" (`docs/plans/2026-10-28-ios-keyboard.md:2061`) and then deferred it to its own sprint
(`docs/plans/2026-10-28-ios-keyboard.md:3900-3903`). No commit has changed the space drag since: Protly runs
KeyboardKit's default drag unchanged.

Diagnosis only. No code changed. Paths starting with `KK/` mean
`ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/`; `KVC` means
`ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`.

## Summary

1. **Movement is dropped, not just slow.** Once the finger is 50 pt above or below the point where the drag
   started, KeyboardKit still counts the horizontal steps but sends none of them, and never sends them later
   (`KK/Gestures/Gestures+SpaceDragGestureHandler.swift:85-91`). 50 pt is less than one key row (54 pt pitch,
   `docs/ios-keyboard-notes.md:234`). Apple's trackpad covers the whole keyboard, so a thumb that drifts upward is
   normal there. With Protly the cursor freezes. This is the most likely cause of the "stalls".
2. **One axis, a fixed 5 pt per character, no acceleration.** Moving 75 characters needs the whole 375 pt
   keyboard width. Because the step is per character, not per point of text, a Hangul syllable (a full-width
   glyph) moves the caret about twice as far on screen as a Latin letter for the same finger travel.
3. **No haptic at the start, and a 0.5 s hold.** Protly turns off every haptic, including the trackpad-start
   tick that Apple gives (`KVC:62-64`). The hold is KeyboardKit's 0.5 s default for every key
   (`KK/_Dependencies/GestureButton/GestureButtonConfiguration.swift:31`).
4. **No vertical movement and no selection.** The API only moves the cursor by character offsets and cannot
   select text (Apple: "it cannot select text"). Vertical movement can only be estimated from the text around the
   cursor. Hard line breaks are exact; soft wraps are a guess.
5. **The word being typed is committed, not lost**, on the first step (`KVC:402-408`). That matches the usual
   IME behavior. The same-turn commit-then-move order has not been checked on the phone (see the checks below).

Ranked fixes (section 5): R1 and R2 are one-line settings in `viewDidLoad`. R3 is a per-key gesture
configuration. R4 is Protly's own drag math, overriding the open `handleDrag` in `ProtlyActionHandler` with a pure,
unit-tested `SpaceTrackpad` in ProtlyCore. None of them touches the vendored tree.

## 1. How space long-press and drag work in Protly today

### The chain of calls

| Step | What happens | Where |
|---|---|---|
| Touch down on space | `DragGesture(minimumDistance: 0)` sees the touch; `.press` goes to the action handler. Space has no press action. | `KK/_Dependencies/GestureButton/GestureButton.swift:159`, `:237-245`; `KK/Actions/KeyboardAction+Actions.swift:50-57` |
| Press | `tryUpdateSpaceDragState(.press)` resets: drag inactive, start point nil | `KK/Actions/Services/KeyboardAction+StandardActionHandler.swift:224`; `KK/Actions/Services/KeyboardAction+StandardActionHandlerSpace.swift:40-60` |
| After `longPressDelay` (0.5 s) | `.longPress` fires unless the finger moved more than `longPressMaxDragDistance` (50 pt) | `GestureButtonConfiguration.swift:31-32`; `GestureButton.swift:304-314` |
| Long press | `isSpaceDragGestureActive = true` (animated). Space's long-press action is a no-op. | `StandardActionHandlerSpace.swift:47`, `:53-55`; `KK/_Keyboard/KeyboardContext.swift:134-145`; `KeyboardAction+Actions.swift:43-47` |
| Keys blank | All key content fades to opacity 0, key backgrounds to 0.5, shadows off | `KK/_Keyboard/KeyboardViewItem.swift:91-93`, `:122-124`; `KK/Styling/KeyboardAction+ButtonColor.swift:32`; `KK/Styling/KeyboardAction+ButtonStyle.swift:84` |
| Haptic | KeyboardKit always asks for haptic on space long press (`return true`), but Protly's configuration is `.disabled`, so the feedback is `.none` | `StandardActionHandler.swift:587`; `KK/Feedback/Feedback+HapticConfiguration.swift:70-76`, `:133-139`; `KVC:62-64` |
| Every touch move | `handleDrag` → `tryHandleSpaceDrag`. The start point is the first move after activation, so movement during the hold is ignored. | `KK/_Keyboard/Views/Keyboard+ButtonGestures.swift:54`, `:291-295`; `StandardActionHandler.swift:248-258`; `StandardActionHandlerSpace.swift:23-38` |
| Step math | `offset = Int((start.x - cur.x) / 5)`; `dy` beyond 50 pt drops the step | `Gestures+SpaceDragGestureHandler.swift:79-92` |
| Sensitivity | `.medium` = 5 pt per step (`.low` 10, `.high` 2, `.custom(points: Int)`); vertical threshold 50 pt | `KK/_Keyboard/Keyboard+Services.swift:97-100`; `KK/_Keyboard/Models/Keyboard+SpaceDragSensitivity.swift:101-108`; `Gestures+SpaceDragGestureHandler.swift:55-56` |
| Emoji | For a ±1 step over an emoji, the offset is multiplied by `utf8.count / 2` | `Gestures+SpaceDragGestureHandler.swift:103-134`; `KK/_Keyboard/KeyboardContext+Proxy.swift:50-52` |
| Move | `controller.adjustTextPosition(by:)` (sign flipped for RTL) → Protly's override → `textDocumentProxy.adjustTextPosition(byCharacterOffset:)` | `Keyboard+Services.swift:152-161`; `KVC:402-408`; `KK/_Keyboard/KeyboardInputViewController.swift:250-252` |
| Release | The space release action is nil while the drag is active, so no space is typed. `.release`/`.end` turns the trackpad off. | `StandardActionHandler.swift:350-359`; `StandardActionHandlerSpace.swift:48` |

Settings in play: `spaceLongPressBehavior` defaults to `.moveInputCursor` (`KK/_Keyboard/KeyboardSettings.swift:97-99`)
and Protly never changes it. The drag sensitivity and threshold are the handler's defaults. Protly sets neither
(no hits for `sensitivity`, `verticalThreshold` or `spaceDrag` under `ios-app/Sources`).

### What protly.patch changes here

Nothing that changes behavior. In this area the patch only wraps `#Preview` blocks
(`ios-app/Vendor/KeyboardKit/protly.patch:288-334` for the three GestureButton files) and gives
`keyboardSpaceLongPressBehavior` an explicit `= nil` (`protly.patch:446-453`). `VENDORED.md` lists no gesture
change (`ios-app/Vendor/KeyboardKit/VENDORED.md:16-27`).

### What Protly does on each step

`KVC:402-408` runs on every step (every 5 pt):

```swift
override func adjustTextPosition(by offset: Int) {
    commitWord()          // first step only: ends the word being typed
    session.forgetLast()  // the bar's flip can no longer reach the last word
    endUndo()
    super.adjustTextPosition(by: offset)
    refreshMode()         // refreshWords + refreshField (reads both contexts, UIPasteboard.changeCount)
}
```

Each move also brings the host callbacks `selectionWillChange` and `selectionDidChange` (KeyboardKit resets
autocomplete at `KeyboardInputViewController.swift:213-221`). Protly's `selectionDidChange` runs
`noticeFieldMoved()` and `refreshField()` again (`KVC:433-437`). So each step reads the pasteboard change count
twice (`KVC:335-351`) and rebuilds the action and suggestion state. KeyboardKit also writes a SwiftUI `@State` on
every touch move (`Keyboard+ButtonGestures.swift:292`). None of this has been measured on the phone. It could add
to the stutter, but there is no evidence yet that it matters as much as items 1-2 in the summary.

### Korean marked text when the drag starts

While a word is being composed it lives as marked text, which the proxy's context does not include (`KVC:29-33`).
The first step's `commitWord()` (`KVC:177-181`) runs `session.commit()`
(`ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift:80-93`): it takes the final language decision, then
`apply(.commit)` does `setMarkedText("")` + `insertText(word)` (`KVC:196-200`), and only then
`adjustTextPosition`. Result:

- The word is **committed** with its final reading, the same as typing a space, and the cursor moves from the end
  of the word. Nothing is lost by design.
- A long press with no movement does nothing: the word stays marked and no space is typed (the release action is
  nil while the drag is active).
- The flip in the bar is disabled for that word (`forgetLast`), as after any cursor move.
- **Unverified:** `KVC:197` records that `unmarkText()` followed by another edit in the same run-loop turn "loses
  the word in every host tested". The `setMarkedText("")` + `insertText` + `adjustTextPosition` order in a single
  turn has not been tested on the phone (phone check P5 below).

## 2. Apple's keyboard: what is documented and what is not

| Aspect | Apple's behavior | Source |
|---|---|---|
| How to start | "Touch and hold the Space bar with one finger until the keyboard turns light gray and the characters on the keys disappear—now it's a trackpad." | [iPhone User Guide, iOS 27: Select, edit, and move text](https://support.apple.com/guide/iphone/select-edit-and-move-text-iph1a9cae52c/ios) |
| Delay | Not documented. Described only as "after a short pause". Accessibility > Touch has Haptic Touch duration and Hold Duration settings; Apple does not say whether they change the space bar's delay. | [statusq.org](https://statusq.org/archives/2025/12/28/); [Apple: Adjust how iPhone responds to your touch](https://support.apple.com/guide/iphone/adjust-how-iphone-responds-to-your-touch-iph77bcdd132/ios); [TidBITS](https://tidbits.com/2024/01/16/adjust-touch-duration-for-haptic-touch-on-the-iphone-and-ipad/) |
| Haptic | "You'll feel a bit of haptic feedback, and you'll notice the cursor gets a bit larger." Not documented by Apple. Whether it follows Settings > Sounds & Haptics > Keyboard Feedback is unverified. | [XDA](https://www.xda-developers.com/how-to-use-iphone-keyboard-trackpad/) |
| Keys blank | Light gray keyboard, the key characters disappear; "blank squares where they were" | Apple guide above; [XDA](https://www.xda-developers.com/how-to-use-iphone-keyboard-trackpad/) |
| Area and directions | "Slide your finger around the trackpad"; "move your finger ... up, down, left, or right"; iOS 12: "Move the insertion point by dragging around the keyboard" | Apple guide above; [XDA](https://www.xda-developers.com/how-to-use-iphone-keyboard-trackpad/); [Apple iPhone User Guide, iOS 12](https://support.apple.com/en-euro/guide/iphone/iph3c50f96e/12.0/ios) |
| Cursor model | The text view gets `beginFloatingCursor(at:)` / `updateFloatingCursor(at:)` / `endFloatingCursor()` with view **points**. The cursor floats freely in 2D over the laid-out text; UIKit's text view places the insertion point from the layout. | [UITextInput.beginFloatingCursor(at:)](https://developer.apple.com/documentation/uikit/uitextinput/beginfloatingcursor(at:)), [updateFloatingCursor(at:)](https://developer.apple.com/documentation/uikit/uitextinput/updatefloatingcursor(at:)), [endFloatingCursor()](https://developer.apple.com/documentation/uikit/uitextinput/endfloatingcursor()) |
| Speed, acceleration | Not documented anywhere I found. Treat as unknown and compare by feel side by side. | none |
| Release | "Once you let go, the cursor stops, and the keyboard reappears again." "To exit the mode, just lift your finger." | [XDA](https://www.xda-developers.com/how-to-use-iphone-keyboard-trackpad/); [Macworld](https://www.macworld.com/article/558720/how-to-iphone-keyboard-trackpad.html) |
| Selection | "Touch and hold the keyboard with a second finger, then adjust the selection by moving the first finger around the trackpad." | Apple guide above |
| Keyboard-area press | On 3D Touch models, "press the keyboard" anywhere (and press deeper to select). iPhone 11 and later have no 3D Touch; there the space bar is the way in (iOS 12 made it so). On iPad, two fingers on the keyboard. | [Apple iPhone User Guide, iOS 12](https://support.apple.com/en-euro/guide/iphone/iph3c50f96e/12.0/ios); [Michael Tsai, iOS 12 beta](https://mjtsai.com/blog/2018/06/26/ios-12-beta-easier-to-access-trackpad-mode/); [statusq.org](https://statusq.org/archives/2025/12/28/) |

The phone in use is an iPhone 13 Pro (`docs/ios-keyboard-notes.md:106`), which has no 3D Touch, so the space bar
long press is the only system entry there.

## 3. Protly against Apple, point by point

| # | Aspect | Apple | Protly today | Effect on feel |
|---|---|---|---|---|
| D1 | Vertical drift | Moves the cursor up and down | Horizontal steps are **dropped** while `abs(dy) >= 50` and never replayed (`Gestures+SpaceDragGestureHandler.swift:88-90`) | Cursor freezes mid-drag when the thumb rises one row; resumes with an offset. Reads as "stall". Proof A |
| D2 | Axes | 2D, line by line | One axis | Multi-line drafts need many back-and-forth drags |
| D3 | Step per point | Floating cursor in points over the laid-out text | 5 pt finger per **character**, whatever its width | English caret ≈ 1.7× finger, Korean ≈ 3.4× (estimate); Korean feels twitchy and English slow. Proof B |
| D4 | Range per press | Whole keyboard in 2D, lines reach far | 375 pt = 75 characters per press, linear | Long trips need several presses, each with a 0.5 s hold. Proof A |
| D5 | Acceleration | Unknown | None | Fast flicks go no farther than slow drags |
| D6 | Steps visible | Continuous floating cursor drawn by the host | Caret jumps whole characters; a keyboard cannot draw in the host | Inherent "steppy" look; it can be reduced (smaller steps for narrow glyphs) but not removed |
| D7 | Delay | "Short pause", undocumented | 0.5 s fixed for every key (`GestureButtonConfiguration.swift:31`) | Possibly slower; measure first (P1) |
| D8 | Start feedback | Haptic tick, keys blank | Keys blank (animated fade); **no haptic** (`KVC:62-64`) | Owner cannot feel when the trackpad is on, so starts dragging too early or waits too long |
| D9 | Selection | Second finger selects | Not possible for a keyboard extension | A missing feature, not something to tune |
| D10 | Marked text | Composition ends at a cursor move (standard IME behavior) | Committed on the first step with its final reading (`KVC:402-408`) | Same as Apple by design; same-turn order unverified (P5) |
| D11 | Emoji steps | Whole graphemes | Multiplier `utf8/2` only on ±1 steps: ❤️ and ☺️ give 3 (UTF-16 length 2), 👨‍👩‍👧 gives 9 (length 8); a step of 2+ never gets the multiplier | Can land inside an emoji or one unit past it, then the next steps look stuck while the host snaps. Proof C |
| D12 | Per-step work | n/a | `refreshMode` + two `refreshField` per step (`KVC:335-351`, `:402-437`) | Unmeasured; possible frame drops on long fields |
| D13 | Other gestures | The long press is only on space | Same. Long press on letters opens callouts, so a keyboard-area trackpad would clash with them. Double-space period cannot fire after a drag (the release action is nil). | No conflict today |

## 4. What a custom keyboard extension can do

The `UITextDocumentProxy` surface is: `documentContextBeforeInput`, `documentContextAfterInput`, `selectedText`,
`adjustTextPosition(byCharacterOffset:)`, `setMarkedText(_:selectedRange:)`, `unmarkText()`,
`documentIdentifier`, `documentInputMode`, plus `UIKeyInput`'s `insertText`, `deleteBackward`, `hasText`
([UITextDocumentProxy](https://developer.apple.com/documentation/uikit/uitextdocumentproxy)). The only cursor call
moves "forward or backward"
([adjustTextPosition(byCharacterOffset:)](https://developer.apple.com/documentation/uikit/uitextdocumentproxy/adjusttextposition(bycharacteroffset:))).
The floating-cursor methods belong to the host's `UITextInput`, not to the proxy. The extension guide says a
custom keyboard "can draw only within the primary view of its UIInputViewController object, it cannot select
text" ([App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)).
Text moves arrive only as `selectionWillChange`/`selectionDidChange` callbacks
([Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)).
Protly already found that hosts apply moves asynchronously (`ios-app/Sources/ProtlyKeyboard/FieldText.swift:14-20`)
and that the offset unit is UTF-16 (`FieldText.swift:13`).

### Ways to get vertical movement

| Option | How | Limits |
|---|---|---|
| V1 Hard lines | Find the previous/next `\n` in the context, keep the column, move by the difference | Exact, but only across real line breaks. Chat drafts are often one long paragraph. |
| V2 Estimated soft wraps | Lay the paragraph out in "units" (narrow glyph 1, Hangul/CJK/emoji 2), wrap greedily at word boundaries at `wrapUnits` per line, move to the same column on the next estimated line, and keep a sticky goal column like editors do | The keyboard knows neither the field width nor the font. Lines drift by a few characters in proportional fonts and differ by host (a Messages bubble is narrower than Notes). The context can stop at a paragraph break (`FieldText.swift:10`); moving past the end of the context just stops. |
| V3 Vertical as coarse travel | dy jumps by words or by `wrapUnits` characters instead of lines | Predictable, but nothing like Apple's line feel |
| V4 Paragraph ends | Vertical flick goes to the paragraph start or end | Simple and exact; coarse |
| Not possible | Pixel-accurate lines, a floating cursor drawn over the host's text, second-finger selection, Apple's own trackpad from a third-party keyboard | No API (see above) |

Proof D (section 6) runs V1+V2 on a mixed English/Korean draft.

### What other iOS keyboards do

- **Gboard (iOS):** "slide your finger back and forth on the spacebar", best "when only moving a little bit": one
  axis ([Gadget Hacks](https://ios.gadgethacks.com/how-to/20-tips-help-you-master-gboard-for-iphone-0182301/)).
  Its 2D "cursor mode" seen in a 2026 beta is reported for Android only
  ([Android Authority](https://www.androidauthority.com/gboard-cursor-mode-3641074/),
  [9to5Google](https://9to5google.com/2026/02/16/gboard-might-finally-add-a-cursor-the-only-good-thing-about-the-iphones-keyboard/)).
- **Microsoft SwiftKey (iOS):** cursor control by "long pressing the spacebar" (or pressing firmly on 3D Touch
  phones). The directions are not documented
  ([Microsoft Support](https://support.microsoft.com/en-us/topic/how-do-i-use-cursor-control-on-my-microsoft-swiftkey-keyboard-748643ba-8485-43ad-9729-8e5c908603e3)).
- **KeyboardKit itself:** horizontal by design, with a vertical threshold that cancels movement
  (`Gestures+SpaceDragGestureHandler.swift:17`, `:89-90`).

I found no iOS third-party keyboard that documents true line-by-line vertical movement. Developers who tried
report the same wall: left/right only, with the line worked out from context text that is not always reliable
([Pythonista forum archive](https://omz-software.com/forum/archive/2303_custom-keyboard-support.html)).

## 5. Proposed changes, ranked

Gain is my estimate of how much closer it feels to Apple. Effort is for the tower's plan. All of them live in
`ios-app/Sources/ProtlyKeyboard` and `ios-app/ProtlyCore`; none needs `protly.patch`, `Package.swift` or `xtool.yml`.

| Rank | Change | Gain | Effort | Fixes |
|---|---|---|---|---|
| R1 | Stop dropping moves: `services.spaceDragGestureHandler.verticalThreshold = .greatestFiniteMagnitude` in `viewDidLoad` (the property is public, `Gestures+SpaceDragGestureHandler.swift:65`) | High | 1 line | D1 |
| R2 | Haptic only at trackpad start: `hapticConfiguration = .init(press: .none, release: .none, doubleTap: .none, longPress: .none, repeat: .none, custom: [.haptic(.selectionChanged, for: .longPress, on: .space)])`. Custom feedback wins (`Feedback+HapticConfiguration.swift:133-139`), and space long press always passes the haptic check (`StandardActionHandler.swift:587`). Try `.selectionChanged`, then `.lightImpact`, then `.mediumImpact` (KeyboardKit's default, `:32`). | Medium-high | 1 line + phone check | D8 |
| R3 | Shorter hold for space only: in `ProtlyRoot`, `buttonView: { $0.view.keyboardButtonGestureConfiguration($0.item.action == .space ? .init(longPressDelay: 0.4) : .standard) }`. The environment reaches the key's `GestureButton` (`Keyboard+ButtonGestures.swift:224`, `GestureButton.swift:106-114`). Try 0.5 → 0.4 → 0.35 after P1 measures Apple. Below about 0.3 s a slow space tap could start the trackpad. | Medium | Small | D7 |
| R4 | Protly's own horizontal math: override the open `handleDrag(on:from:to:)` (`StandardActionHandler.swift:248`) in `ProtlyActionHandler` for `.space` while `keyboardContext.isSpaceDragGestureActive`, and call a pure `SpaceTrackpad` in ProtlyCore. (1) Cost per **grapheme** by width: 6 pt narrow, 12 pt Hangul/CJK/emoji. (2) Keep the remainder between events (no truncation). (3) Speed gain 1× below 100 pt/s, rising linearly to 3× at 600 pt/s. (4) Offsets in UTF-16 units of whole graphemes. (5) Clamp at the ends of the context. (6) Work on a snapshot taken at drag start (`before + marked + after`, caret after the mark) rather than re-reading the proxy, which lags behind the host. | High | Medium | D3, D4, D5, D11, part of D6 |
| R5 | Lighter steps: while `isSpaceDragGestureActive`, skip `refreshMode`/`refreshField` in `adjustTextPosition` and `selectionDidChange`; refresh once on `.end`. Measure first (P6). | Unknown until measured | Small | D12 |
| R6 | Vertical: V1 + V2 with a sticky goal column. Every 24 pt of dy is one line (try 20/24/30); `wrapUnits` 40 for a 390 pt phone (try 34-44); horizontal and vertical accumulate independently, and neither cancels the other. Ship behind a setting until it has been used for a while. | High for multi-line drafts | Medium-high | D2 |
| R7 | Quick experiment if R4 waits: `sensitivity = .custom(points: 4)` or `6`. It is an integer, so there is no 1.5× in between, and the same value applies to Korean and English. Mostly useful to learn which step the owner prefers before R4. | Low-medium | 1 line | D3 (partly) |

Order to build: R1 + R2 together (they are independent and tiny), then P1 to set R3, then R4 (with R5 if P6 shows
cost), then R6.

### Unit tests (ProtlyCore, `swift test --package-path ios-app/ProtlyCore`)

`SpaceTrackpad` as a value type with `mutating func move(dx:dy:dt:) -> Int` over a snapshot. Proposed tests:

- `testSlowDragMovesOneNarrowCharacterPerSixPoints`: 30 pt at 50 pt/s over `"hello world"` → +5.
- `testWideGlyphCostsTwice`: 24 pt slow over `"가나다라"` → +2.
- `testRemainderCarriesAcrossEvents`: ten 1 pt events → +1 (KeyboardKit's absolute mapping hides this; ours must keep it).
- `testReverseWithinAStepDoesNotJitter`: +4 pt then −4 pt → 0 net calls.
- `testFastFlickIsCappedAtMaxGain`: 60 pt in 0.1 s → +30, not more.
- `testStopsAtContextEnds`: no offset past the end of `after` or the start of `before`.
- `testWholeGraphemesInUTF16`: one step over ❤️ → 2, over 👨‍👩‍👧 → 8, over 🇰🇷 → 4, over 가 → 1.
- `testVerticalDriftKeepsHorizontal`: dx −100 pt with dy −60 pt → the same horizontal result as dy 0 (the D1 regression).
- `testMarkedWordIsInTheSnapshot`: before `"오늘 "`, marked `"진짜"`, after `""` → the first −1 lands between 진 and 짜.
- R6: `testLineDownKeepsColumnAcrossHardBreak`, `testLineToShorterLineClampsToItsEnd`, `testGoalColumnIsSticky`
  (down to a short line and down again returns to the original column), `testSoftWrapEstimateAtWrapUnits`,
  `testNoLineBeyondContextMovesNothing`.

### Phone checks (what the owner should feel)

Same text in Instagram DM, KakaoTalk and Messages, Apple's keyboard and Protly side by side:

- **P1 Delay:** film both keyboards with another phone's slow-motion camera; count frames from touch to the keys
  going blank. Set R3 to Apple's figure (rounded to 0.05 s).
- **P2 Haptic (R2):** one tick exactly when the keys blank, none on any other key. Also check whether Apple's
  keyboard ticks with Keyboard Feedback > Haptic off; if it does not, Protly's tick should become a toggle.
- **P3 No freeze (R1):** hold space, drag left across the whole keyboard while the thumb rises to the top row. The
  cursor keeps moving the whole time.
- **P4 Feel (R4):** in a 3-line English draft and a 3-line Korean draft, put the cursor 10 characters back slowly,
  then flick to the start of the line. Slow should feel as precise as Apple's; the flick should reach about 40
  characters in one stroke; Korean and English should feel equally fast on screen.
- **P5 Marked text:** type `안녕` with no space, hold space, drag left one step, release: the field shows `안|녕`
  (cursor between) and nothing is lost, in all three hosts. Repeat with an English word.
- **P6 Cost:** a debug build logs the time inside `adjustTextPosition` and `selectionDidChange` during a drag (the
  same Console route as ProtlyHeight's log, `docs/ios-keyboard-notes.md:324-326`). If a step costs more than about
  4 ms, R5 is needed.
- **P7 Vertical (R6):** in a long one-paragraph message, drag up and down. Each 24 pt should move about one visual
  line and land near the same column; in a draft with blank-line paragraphs the hard breaks should be exact.

## 6. Proofs (throwaway scripts, not committed)

Node.js ports of the code paths; run with `node`. There is no Swift toolchain in this session.

### A. KeyboardKit's step math drops moves and caps the range

```js
// Port of Gestures+SpaceDragGestureHandler.swift:79-92, sensitivity .medium = 5 pt, verticalThreshold 50.
export function kkHandler(points = 5, verticalThreshold = 50) {
  let applied = 0, moved = 0, lost = 0;
  return {
    drag(start, cur) {
      const textPositionOffset = Math.trunc((start.x - cur.x) / points);   // Int(dragDelta / points)
      if (textPositionOffset === applied) return 0;
      const offsetDelta = textPositionOffset - applied;
      applied = textPositionOffset;                                       // updated even when the move is dropped
      if (Math.abs(start.y - cur.y) >= verticalThreshold) { lost += -offsetDelta; return 0; }
      moved += -offsetDelta;
      return -offsetDelta;
    },
    get moved() { return moved; }, get lost() { return lost; },
  };
}
```

Finger paths sampled at 120 Hz:

```
A right 100 pt: moved 20, dropped 0
B one press, finger from the left edge to the right edge (375 pt): moved 75
C left 100 pt while drifting up 60 pt: moved -16, dropped -4
D up 55 pt, left 100 pt, back down, left 25 pt: moved -5, dropped -20
```

D is the stall: 100 pt of finger travel moves nothing, and the cursor does not catch up when the finger comes
back down.

### B. Same step, different on-screen speed

```
caret travel per 1 pt of finger, Latin (about 8.5 pt per letter at 17 pt, estimate): 1.7 pt
caret travel per 1 pt of finger, Hangul (about 17 pt per syllable at 17 pt, estimate): 3.4 pt
```

The glyph widths are my estimates for a 17 pt text font (assumed, not measured; hosts differ). The point is the
ratio of about 2 between a full-width syllable and a Latin letter.

### C. Emoji multiplier against UTF-16 length

```js
const enc = new TextEncoder();
for (const e of ['😀', '👍🏽', '❤️', '🇰🇷', '👨‍👩‍👧', '☺️'])
  console.log(`${e}: utf8 ${enc.encode(e).length} -> multiplier ${Math.floor(enc.encode(e).length / 2)}, utf16 ${e.length}`);
```

```
😀: utf8 4 -> multiplier 2, utf16 2
👍🏽: utf8 8 -> multiplier 4, utf16 4
❤️: utf8 6 -> multiplier 3, utf16 2
🇰🇷: utf8 8 -> multiplier 4, utf16 4
👨‍👩‍👧: utf8 18 -> multiplier 9, utf16 8
☺️: utf8 6 -> multiplier 3, utf16 2
```

Emoji with a variation selector or ZWJ overshoot by one UTF-16 unit. Plain emoji and flags happen to match.

### D. Prototype of R4 and R6

Core of the horizontal step (the R4 math; width-aware cost, remainder kept, speed gain):

```js
export const cfg = { pointsPerNarrow: 6, wideFactor: 2, v0: 100, v1: 600, maxGain: 3, lineStep: 24, wrapUnits: 40 };
export function gain(speed, c = cfg) {
  if (speed <= c.v0) return 1;
  if (speed >= c.v1) return c.maxGain;
  return 1 + (c.maxGain - 1) * (speed - c.v0) / (c.v1 - c.v0);
}
export function horizontal(state, dx, dt, before, after, c = cfg) {
  const speed = Math.abs(dx) / Math.max(dt, 1e-3);
  let acc = state.acc + dx * gain(speed, c), offset = 0;
  const b = graphemes(before), a = graphemes(after);
  for (;;) {
    const ch = acc > 0 ? a[0] : b[b.length - 1];
    if (ch === undefined) { acc = 0; break; }                       // at the field's edge: drop the rest
    const cost = c.pointsPerNarrow * (isWide(ch) ? c.wideFactor : 1);
    if (Math.abs(acc) < cost) break;
    if (acc > 0) { offset += ch.length; b.push(a.shift()); acc -= cost; }
    else { offset -= ch.length; a.unshift(b.pop()); acc += cost; }
  }
  return { state: { acc }, offset };
}
```

```
slow (60 pt in 1 s): English 10 chars, Korean 5 syllables (UTF-16 units)
fast (60 pt in 0.1 s): English 30 chars, Korean 15 syllables (UTF-16 units)
fast 300 pt flick, English: 150 chars (KeyboardKit .medium: 60)
```

Vertical (V1 hard breaks + V2 greedy word wrap at 40 units, wide glyphs 2 units), on
`hello there, this is a long first line that wraps on a phone screen\n오늘 진짜 길었어 내일 아침에 전화할게 늦으면 미안\nok`,
caret after `this is`:

```
start "ere, this is| a long firs"
down  39 "ps on a phon|e screen\n오늘 "
down  21 "오늘 진짜 길었어 내일| 아침에 전화할게 늦으"
down  16 " 전화할게 늦으면 미안|\nok"
up    -21 "reen\n오늘 진짜 길|었어 내일 아침에 전화"
```

The last line shows why the plan needs a sticky goal column: after landing at the end of a short line, the
prototype goes back up from that shorter column (`길|었어`), not from the original one (`내일|`). Editors keep the
goal column until a horizontal move. The wrap points are estimates; the real field may break one word earlier or
later.

## 7. Open questions

- Apple's hold delay, cursor gain and acceleration are undocumented (P1, P4 give numbers to aim at).
- Whether Apple's trackpad haptic follows the Keyboard Feedback switch (P2).
- Whether committing and moving in one run-loop turn is safe in every host (P5).
- How much of the stutter is per-step work rather than the step math (P6).
- Whether the drag keeps tracking when the finger leaves the keyboard's top edge into the host app. SwiftUI's
  `DragGesture` keeps the touch that began in the view, but this has not been checked on the phone (check during P3).
