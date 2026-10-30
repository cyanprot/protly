# Edit menu missing while Protly is active

Research only, 2026-10-30. No code, test or workflow was changed. The one throwaway script is quoted below and is
not committed. No iOS device or simulator was available to this session (Linux, no Swift toolchain), so every
claim about iOS behaviour comes from a cited source. The simulator scenario in "Test plan" is how to prove it.

WebKit source is cited at commit `5a14691684cdc0da018e7d0de2f5f3bf18016e8d` (`main` on 2026-10-30), shortened to
`WK@5a14691` below. Base URL: `https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/`.

## Summary

- **Most likely cause (H1): a word Protly is still composing is live marked text when the user long-presses or
  double-taps.** Protly keeps every word as marked text, English as well as Korean, until a space, punctuation,
  return, a bar action or a cursor move commits it. The last word of a message usually has no space after it, so
  the field still holds marked text when the user goes to select. Touches near marked text go to the system's
  marked-text handling, not to word selection, so no edit menu is presented. In WebKit this is in the source
  ("near" means within 66 pt of the composition). For UIKit hosts it rests on an Apple forum thread from June 2026
  (iOS 27 beta) and on azooKey's notes. Apple's English keyboard never leaves marked text, which fits "only while
  Protly is active". It also fits "sometimes": it only happens when the last word has not been committed.
- **H2:** the user selects text away from the marked word while the input session still has marked text. The
  selection highlight shows, but whether UIKit presents the menu while a keyboard extension's marked text is still
  open is not documented anywhere I could find. On iOS, WebKit does not end the composition when the selection
  changes.
- **H3 (a real bug, and it makes H1 last longer):** after the user taps or selects, `noticeFieldMoved` can keep
  the word "composing" when the text before the cursor has not changed, for example after double-tapping the word
  just typed. Protly then still holds `marked`, and the next key re-marks the whole word over the selection.
- **What Protly does not do:** it never calls `setMarkedText`, `insertText`, `deleteBackward` or
  `adjustTextPosition` from a host callback (`textDidChange`, `selectionDidChange`), from the bar refresh or from
  the word-list or lexicon loads. Every write to the field follows a key, a bar tap or a panel tap. "The keyboard
  moves the selection after the user's tap" is ruled out for the current code.
- Platform rules that look like this bug but are not: Select All is hidden by design when a range is selected, and
  Paste needs pasteboard content.
- **Fix direction:** first fix the stale state, which is cheap and testable in ProtlyCore. Then, once the
  simulator scenario confirms H1, shorten how long a word stays marked: commit after a short idle pause, or mark
  only the Hangul syllable being composed.

## 1. What Protly does to marked text and the selection

### 1.1 How long a word stays marked

- `TypingSession.type` returns `.mark(render(keys))` for every letter key, in whichever language is decided
  (`ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift:56-61`). So an English word is marked text too, and
  the whole word is marked, not only the Hangul syllable being composed.
- `apply(.mark(text))` calls `proxy.setMarkedText(text, selectedRange: end)` and mirrors the text in `marked`
  (`ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift:193-195`).
- The mark ends only through `commit()` (`TypingSession.swift:80-92`) or `accept()` (`TypingSession.swift:97-105`).
  Both are applied as `setMarkedText("")` followed by `insertText(text)` (`KeyboardViewController.swift:196-200`).
  Those run from:
  - KeyboardKit text calls, which Protly intercepts: `insertText` (space, punctuation, return),
    `deleteBackward`, `adjustTextPosition` (space-drag cursor) and `endSentence`
    (`KeyboardViewController.swift:378-415`). The space drag reaches the controller's `adjustTextPosition` through
    `ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/_Keyboard/Keyboard+Services.swift:153-160`.
  - `act` (protly key or bar action) (`KeyboardViewController.swift:210-211`) and `pickSuggestion`
    (`KeyboardViewController.swift:146-154`).
- Nothing commits on a timer, on a host callback or when the keyboard hides. `viewWillDisappear` drops the word
  (`session.abandon()`, `marked = ""`) without writing to the field
  (`KeyboardViewController.swift:99-109`). The comment there says the host keeps the word as text. Whether the
  host also ends the *mark* is not checked anywhere.

### 1.2 Every path that touches the field, and what triggers it

| Path | Field writes | Trigger | Code |
|---|---|---|---|
| `typeLetter` -> `apply(.mark)` | `setMarkedText` | letter key | `KeyboardViewController.swift:113-125`, `193-195` |
| `backspaceInWord` -> `apply(.mark)` / `.mark("")` | `setMarkedText`, plus `setMarkedText("")`, `insertText`, `deleteBackward` x n for the last jamo | backspace key | `KeyboardViewController.swift:128-135`, `187-192` |
| `flipWord` -> `.mark` or `.replace` | `setMarkedText`, or `deleteBackward` x n + `insertText` | bar left slot | `KeyboardViewController.swift:137-143`, `201-203` |
| `commitWord` -> `.commit` | `setMarkedText("")` + `insertText` | KeyboardKit text calls, `act` | `KeyboardViewController.swift:177-181`, `378-415` |
| `FieldText.read` | `adjustTextPosition` (up to 10 jumps to the end) | protly key or bar action, only with no selection | `ios-app/Sources/ProtlyKeyboard/FieldText.swift:8-26` |
| `insertResult`, `undoInsert` | `insertText`, `deleteBackward` | panel taps | `KeyboardViewController.swift:285-322`, `FieldText.swift:29-36` |
| KeyboardKit space drag, `moveCursorBackward/Forward` | `adjustTextPosition` (through the override, which commits first) | key gestures | `Keyboard+Services.swift:153-160`, `ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Actions/KeyboardAction+Actions.swift:69-70` |

Host callbacks, refreshes and background work, which never write to the field:

| Path | What it does | Code |
|---|---|---|
| `textWillChange` (KeyboardKit) | re-syncs the proxy reference | `ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/_Keyboard/KeyboardInputViewController.swift:223-226` |
| `textDidChange` | KeyboardKit schedules `textDidChangeAsync` (autocomplete, keyboard case), then Protly runs `noticeFieldMoved` and `refreshField` | `KeyboardInputViewController.swift:228-245`, `KeyboardViewController.swift:427-431` |
| `textDidChangeAsync` | skipped while composing | `KeyboardViewController.swift:439-443` |
| `selectionWillChange` / `selectionDidChange` | KeyboardKit resets autocomplete, then Protly runs `noticeFieldMoved` and `refreshField` | `KeyboardInputViewController.swift:213-221`, `KeyboardViewController.swift:433-437` |
| `noticeFieldMoved` | reads `documentContextBeforeInput` and `hasText`; may `abandon()` or `forgetLast()`; no writes | `KeyboardViewController.swift:160-174` |
| `refreshField` / `refreshMode` / `refreshWords` | read the context and the pasteboard's `changeCount` / `hasStrings`; set `@Published` bar state | `KeyboardViewController.swift:335-361`, `ios-app/Sources/ProtlyKeyboard/Words.swift:36-46` |
| detector load, lexicon arrival | `refreshMode()` | `KeyboardViewController.swift:72-84`, `Words.swift:22-33` |
| `ProtlyHeight` | changes the height pin only at load, at re-presentation and on `NSExtensionHostDidBecomeActive` within 2 s of load | `ios-app/Sources/ProtlyKeyboard/ProtlyHeight.swift:44-58`, `96-103` |

KeyboardKit itself never calls `setMarkedText` or `unmarkText`. The only match in the vendored tree is the preview
stub (`ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Previews/KeyboardPreviews+Proxy.swift:39-40`).
`replaceCurrentWord`, which calls `adjustTextPosition`, is used only by autocomplete
(`ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Proxy/UITextDocumentProxy+Words.swift:69-73`), and Protly never
applies KeyboardKit autocomplete suggestions.

### 1.3 The stale "composing" state after a tap or a selection

`noticeFieldMoved` keeps the word when `hasText && before == wordStartBefore`
(`KeyboardViewController.swift:163-164`). `wordStartBefore` is the text before the word, taken at its first key
(`KeyboardViewController.swift:116`). The proxy's context does not include the marked text
(`KeyboardViewController.swift:29-33`). The check never looks at `selectedText`. A throwaway model of that branch
(not committed):

```python
def notice(composing, has_text, before, word_start_before):
    if composing:
        if not (not has_text or before != word_start_before):
            return "keep composing (marked kept)"
        return "abandon (no field write)"
```

With `오늘 ` before a marked `안녕`:

```
caret after the word, host committed mark               -> abandon (no field write)
double-tap selects 안녕 (selection starts at word)        -> keep composing (marked kept)
long-press puts caret at word start                     -> keep composing (marked kept)
mark vanished (forum 833053), caret at word start       -> keep composing (marked kept)
selection of 오늘 (starts at 0)                           -> abandon (no field write)
field holds only the mark (no other text)               -> abandon (no field write)
```

In the three "keep" rows Protly believes the word is still in the field as its mark. The next letter calls
`setMarkedText("안녕" + key)` (`KeyboardViewController.swift:193-195`), which replaces whatever the host now has
selected with the old word plus the new letter. A bar action with a selection first runs `commitWord`
(`KeyboardViewController.swift:211`), which writes `setMarkedText("")` + `insertText("안녕")` over the
selection, so `FieldText.read` then finds no selection and reads the whole field
(`FieldText.swift:9`).

azooKey's author reports that while marked text exists, a keyboard is not told when the user moves the cursor or
selects text: `textWillChange` / `textDidChange` are not called (see 2.4). If that still holds, even the "abandon"
rows may never run, and the mark lives on until the next key.

## 2. How the platform decides

### 2.1 The menu belongs to the host

Apple: a custom keyboard "cannot select text", "text selection is under the control of the app that is using the
keyboard", and the host's editing menu is out of the keyboard's reach
([App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)).
A keyboard can only influence the menu indirectly, through the text, the marked text and the cursor that it
changes through the proxy. Apple also documents that `setMarkedText` selects text: "Calling `setMarkedText`
selects the text specified by `range`. Subsequent insertions replace the characters selected in the range"
([Handling text interactions in custom keyboards](https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards)).

### 2.2 WebKit (Safari, Gmail on the web, in-app browsers, any WKWebView host)

- **Gestures near marked text.** `-[WKContentView pointIsNearMarkedText:]` answers UIKit's question with
  `_positionInformation.isNearMarkedText`
  ([`WKContentViewInteraction.mm:3622-3644`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L3622-L3644)).
  The BrowserEngineKit variant `isPointNearMarkedText:` forwards to it
  ([`WKContentViewInteraction.mm:13818-13820`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L13818-L13820)).
  The web process sets the flag only while the editor has a composition. It clamps the touch to the composition's
  range and calls the touch "near" when it is within 66 pt horizontally of that caret, and within 66 pt of its top
  or bottom
  ([`PositionInformationForWebPage.mm:97-126`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/WebProcess/WebPage/Cocoa/PositionInformationForWebPage.mm#L97-L126)).
  Apple's documentation of the same hook says: "The system uses the value you return to determine whether to begin
  text interaction gestures that occur close to the marked text"
  ([BETextInput isPointNearMarkedText(_:)](https://developer.apple.com/documentation/browserenginekit/betextinput/ispointnearmarkedtext(_:))).
  In a one-to-three-line chat field, the end of the message, where the user was just typing, is inside that zone.
- **On iOS, WebKit does not end a composition when the selection changes.** The code that abandons "the current
  inline input session if selection changed" sits inside `#if HAVE(TOUCH_BAR)`, so it is macOS only
  ([`WebPage.cpp:8174-8205`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/WebProcess/WebPage/WebPage.cpp#L8174-L8205)).
  On iOS the composition stays until the input system (here, the keyboard through the proxy) ends it.
- **Copy needs a range selection** (`editorState.selectionType == Range`)
  ([`WKContentViewInteraction.mm:4787-4793`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L4787-L4793)).
  **Select All is hidden for a range selection** "by platform convention"
  ([`WKContentViewInteraction.mm:4880-4885`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L4880-L4885)).
  Neither rule looks at the composition.
- **A selection geometry change updates the selection UI.** `_updateChangedSelection` refreshes `_markedText` and
  calls `[textInteractionWrapper selectionChanged]` when the selection looks different
  ([`WKContentViewInteraction.mm:9479-9505`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L9479-L9505)).
  An open-source editor measured this on iOS 26 (iPhone 15): the edit menu is dismissed when "the rendered
  rectangles of the selected range change", and nothing short of a real touch brings it back
  ([cybersemics/em#5642](https://github.com/cybersemics/em/pull/5642)). Every `setMarkedText` changes those
  rectangles, but Protly only calls it on a key press (1.2).

### 2.3 UIKit hosts (Messages, KakaoTalk, Instagram DM, the CI host)

UIKit's text interaction is closed source. The closest public evidence:

- Apple Developer Forums,
  [thread 833053](https://developer.apple.com/forums/thread/833053) (June 2026, iOS 27 beta): with a keyboard
  extension that uses `UITextDocumentProxy.setMarkedText`, "when the marked text is touched, or when the cursor is
  moved between the text, the marked text will be disappear". The steps are "Touch the marked text or long press
  the cursor to move to the marked text". An Apple engineer answered that such a keyboard "will also work with the
  phrase boundary navigation that is present in the document" and asked for a Feedback report. So a touch on
  marked text goes to a marked-text navigation path, not to normal selection.
- Neither that thread nor any other source I found says outright that the edit menu is suppressed while marked
  text exists in a UIKit text view. Section 4's scenario measures it.

### 2.4 Other custom keyboards

- azooKey (an open-source Japanese iOS keyboard), "iOSカスタムキーボードのsetMarkedTextの現状"
  ([zenn.dev/azookey](https://zenn.dev/azookey/articles/896fb7b52bf13b)): the user can select text and move the
  cursor, "しかしmarked textがある状態ではこれらのユーザの操作を検知する機構が使えなくなる" (but while marked text
  exists, the mechanism that detects those operations is unavailable); `textDidChange` "is not called" then. The
  same article says WebKit fields give completely different results, and that iOS 13 to 14.3 made marked text
  vanish on tap. Its follow-up says tap-to-vanish "has never been fixed" and comes and goes between versions, and
  azooKey ships marked text only as an opt-in experiment
  ([zenn.dev/en3_hcl](https://zenn.dev/en3_hcl/articles/96c2d043fdaeac)). The test project is
  [ensan-hcl/ExploreSetMarkedText](https://github.com/ensan-hcl/ExploreSetMarkedText).
- taigikeyboard (an open-source Taiwanese keyboard): UIKit hosts send `textDidChange` about 50-70 ms after
  `unmarkText()` on non-empty marked text, and proxy calls made in one main-thread turn reach the host merged on
  iOS 27 ([taigikeyboard/taigikeyboard#375](https://github.com/taigikeyboard/taigikeyboard/pull/375)). This
  matters for any fix that commits the mark: Protly will see its own commit come back as a late callback.
- KeyboardKit: no issue about marked text or the edit menu turned up
  ([KeyboardKit issues](https://github.com/KeyboardKit/KeyboardKit/issues)). That is expected, because KeyboardKit
  never marks text (1.2).
- Apple Community threads about a missing copy/paste menu suggest removing third-party keyboards as a first test
  ([discussions.apple.com/thread/254385087](https://discussions.apple.com/thread/254385087)). That is anecdotal
  and does not explain the mechanism.

## 3. Candidate causes, ranked

### H1: live marked text at the moment of the gesture (high)

1. The field holds `오늘 `. The user types `dkssud`. Each key runs `setMarkedText` (`KeyboardViewController.swift:193-195`),
   so the host now has the marked text `안녕`, underlined.
2. The user does not type a space, which is the normal state after the last word of a message, and long-presses
   or double-taps a word to copy or fix it.
3. The touch is near the marked text (WebKit: within 66 pt, 2.2; UIKit: forum 833053, 2.3). The system starts
   marked-text navigation instead of word selection: the caret moves into or next to the mark, or the mark
   vanishes. No range is selected, so there is no menu.
4. Protly is not told (2.4), or `noticeFieldMoved` keeps composing (1.3). Nothing commits the mark, so every
   further gesture near it fails the same way until the user presses a key that commits: space, punctuation,
   return, or a bar action.

The same happens after an English word, because English words are marked too (`TypingSession.swift:56-61`).
Hosts: WebKit for certain, inside the 66 pt zone. UIKit hosts (Messages, KakaoTalk, Instagram DM) are probable,
and the scenario confirms it. "Only with Protly": Apple's English keyboard does not leave the word as marked text.

### H2: a selection made while the inline session is still open (medium)

1. As in H1, steps 1-2, but the user double-taps a word far from the mark (outside the near zone), or drags the
   selection handles.
2. The host draws a selection. The composition is still open: WebKit does not end it on iOS (2.2), and Protly
   does not end it (1.1).
3. Whether UIKit presents the edit menu for a range selection while a keyboard extension's marked text is still
   open is not documented. If it does not, the owner sees exactly "text selected, no menu".

Hosts: all, if real. The scenario separates H2 from H1 by selecting far from the mark (S3 below).

### H3: stale composing state after the gesture (high as a bug, medium as a cause)

1. As in H1, steps 1-2. The user double-taps `안녕` itself, or long-presses to the start of the word.
2. `before == wordStartBefore` and `hasText`, so `noticeFieldMoved` returns early. The session is still composing
   and `marked` is still `안녕` (`KeyboardViewController.swift:163-164`, model in 1.3).
3. The edit menu may show this time. The next letter or bar action writes the old word over the selection (1.3),
   and the keyboard keeps treating the field as having a mark, so the next word's touches fall into H1 again.

Hosts: all. This needs no undocumented platform behaviour. It follows from the code.

### H4: a keyboard frame or height change while the menu is up (low)

`ProtlyHeight` changes the height pin by 17 pt when `NSExtensionHostDidBecomeActive` arrives within 2 s of the
controller loading (`ProtlyHeight.swift:96-103`). That happens after an app switch, not during a selection. Bar and
layout re-renders on `refreshMode` (`KeyboardViewController.swift:355-361`) keep the pinned height. Whether a
keyboard frame change dismisses the host's menu is not documented. The scenario logs `ProtlyHeight`'s `bounds`
lines, so any height change during the selection steps would show.

### Ruled out or not a bug

- **The keyboard changes the selection after the tap.** No host callback, refresh or load writes to the field
  (1.2). `FieldText.read` moves the cursor only on a protly or bar tap, and never when a selection exists
  (`FieldText.swift:9-13`).
- **"Select All" missing with a range selected**: platform convention
  ([`WKContentViewInteraction.mm:4880-4885`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L4880-L4885)).
- **"Paste" missing**: needs pasteboard content
  ([`WKContentViewInteraction.mm` `canPerformActionForWebView:`](https://github.com/WebKit/WebKit/blob/5a14691684cdc0da018e7d0de2f5f3bf18016e8d/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L4734)).
  Protly's `refreshField` only reads `changeCount` and `hasStrings` (`KeyboardViewController.swift:344-351`), which
  does not change the pasteboard.

## 4. Fixes (for the tower to plan) and test plan

### 4.1 Fixes and trade-offs

| # | Fix | Helps | Trade-offs |
|---|---|---|---|
| F1 | `noticeFieldMoved` also abandons when `selectedText` is non-empty, and treats any `selectionDidChange` that Protly did not cause as a move. Put the decision in ProtlyCore as a pure function. | H3; removes the stale `marked` | Protly's own `setMarkedText` and commits also produce callbacks, some 50-70 ms late (taigikeyboard#375), so it needs a short "own edit" window or a check against the expected context. Without that, a late callback would abandon the word mid-typing. |
| F2 | When F1 decides the field moved while a mark may still be in the host, end it the safe way: `setMarkedText("")` + `insertText(marked)` (the pattern at `KeyboardViewController.swift:196-200`). | H1 and H2 after the first gesture; an orphaned mark after hide | Writing at a moved cursor can put the word in the wrong place, or twice if the host already committed it. Needs the context check first. It cannot rescue the first gesture: the system decides "near marked text" before the keyboard hears anything. |
| F3 | Commit the word after a short idle pause (for example 1-2 s with no key) as plain text, keeping `last` so the bar can still flip it through `.replace`. | H1 and H2 at the source; nothing is marked when the user stops to select | A pause inside a word splits it: 안 + pause + ㄴ composes as a new word. That needs "re-open the last word if the next key continues it" (delete and re-mark), which brings back the replace risks in WebKit hosts. Detection and suggestions see the word as complete earlier. |
| F4 | Mark less: keep only the Hangul syllable being composed as marked text, and insert English letters and finished syllables as plain text, changing the word through delete + insert. | H1 and H2 for English words, and most of a Korean word | The largest change. Flip and language switching mid-word become delete + insert of committed text, which azooKey found fragile, especially in WebKit. |
| F5 | Leave it, and tell the user to type a space before selecting. | none | Zero risk. Not a fix. |

Recommendation: F1 now, since it fixes a real bug either way and can be unit tested. Then let the simulator
scenario decide. If S1 fails and S2 passes (H1 confirmed), F3 is the smallest change that removes the cause. F2 is
a supporting piece for both.

### 4.2 Unit tests (ProtlyCore, `swift test --package-path ios-app/ProtlyCore`)

The move decision lives in the keyboard target today (`KeyboardViewController.swift:160-174`), which ProtlyCore
tests cannot reach. With F1, a pure function, for example
`FieldWatch.decide(composing:hasText:before:wordStartBefore:selected:lastTail:) -> .keep | .abandon | .forgetLast`,
gets these cases:

- composing, `before == wordStartBefore`, `selected == "안녕"` -> `.abandon` (today: keep; the H3 regression).
- composing, `before == wordStartBefore`, `selected == ""`, `hasText` -> `.keep` (ordinary typing; the mark is
  not in the context).
- composing, `before != wordStartBefore` -> `.abandon`.
- composing, `!hasText` -> `.abandon` (Sprint 4 item 1 depends on this; see the comment at
  `KeyboardViewController.swift:159`).
- not composing, `lastTail` no longer a suffix -> `.forgetLast`.
- If F3: `TypingSession` idle commit returns `.commit(text)` and keeps `last`, a later `flip()` returns
  `.replace`, and a key after the idle commit starts a new word.

A source-rule test in the style of `KeyboardSourceRulesTests` (which already reads the keyboard sources as text,
`ios-app/ProtlyCore/Tests/ProtlyCoreTests/KeyboardSourceRulesTests.swift:8-30`) would guard the "no writes from
host callbacks" finding. The bodies of `textDidChange`, `selectionDidChange`, `selectionWillChange`,
`textWillChange` and `refreshField` must not contain `setMarkedText`, `insertText`, `deleteBackward`, `unmarkText`
or `adjustTextPosition`. If F2 is adopted, the test names the one function allowed to write.

### 4.3 Simulator scenario (keyboard-shots CI)

Where: a new `test6_editmenu` in `ios-app/CI/UITests/PhoneChecksUITests.swift`, using `Driver.type`,
`clearField`, `fieldText`, `switchToEnglish` and `pick(.protly)` (`ios-app/CI/UITests/Driver.swift:206-275`,
`333-402`). The edit menu belongs to the host app, so XCUITest can query it, unlike Protly's own keys. The CI host
field is a SwiftUI `TextField(axis: .vertical)` (`ios-app/CI/Host/HostApp.swift:23-30`), a UIKit host.

Sketch (not committed; item IDs are placeholders):

```swift
/// The host's edit menu, if any. iOS 16+ presents it with UIEditMenuInteraction; query menu items and buttons,
/// and dump the tree once so the first run shows which element type the runtime uses.
func editMenu(_ d: Driver) -> [String] {
    let labels = ["Copy", "Cut", "Paste", "Select All", "Select", "Look Up", "Translate"]
    var seen: [String] = []
    for l in labels where d.app.menuItems[l].exists || d.app.buttons[l].exists { seen.append(l) }
    d.dumpOnce("edit-menu")
    return seen
}

/// Selects with a double-tap at `x` (fraction of the field's width) on the field's first line.
func doubleTapField(_ d: Driver, x: CGFloat) {
    d.field.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).doubleTap()
    d.pause(1.0)   // the menu appears after the gesture ends
}

func checksEditMenu() {
    // S0 control, Apple's keyboard: "hello there", double-tap "hello" -> Copy expected.
    // S1 H1: Protly, "안녕 오늘" with no space, double-tap ON the last word (inside the mark).
    var it = Item("em-1")
    d.clearField(); d.type("안녕 오늘")
    doubleTapField(d, x: 0.25)                  // on 오늘; tune x from the first run's screenshot
    it.require("menu", editMenu(d).contains("Copy"), "\(editMenu(d))")
    it.noteField("after", field())              // did the mark vanish (forum 833053)?
    finish(it)
    // S2 control for S1: the same text with a trailing space (mark committed) -> Copy expected.
    // S3 H2: "안녕하세요 오늘" with no space, double-tap the FIRST word (far from the mark).
    // S4 H3: S1, then type "ㅎ" -> the field must read "안녕 ㅎ" (selection replaced), not "안녕 오늘ㅎ".
    // S5 English: S1 with "hello there" typed on Protly (English words are marked too).
    // S6 long-press instead of double-tap for S1 and S3: press(forDuration: 1.0), then look for "Select" / "Paste".
}
```

Reading the results:

| S0 | S1 | S2 | S3 | Conclusion |
|---|---|---|---|---|
| menu | none | menu | menu | H1 confirmed: the live mark at the touch. F3 (+F1/F2). |
| menu | none | menu | none | H1 and H2: any open composition blocks the menu. F3 or F4. |
| menu | menu | menu | menu | Not reproduced in UIKit; run the WebKit host and an app-switch variant (H4). |
| none | - | - | - | Simulator or harness problem (the control failed); fix the harness first. |

S4 tests H3 directly from the field text, with no menu involved. A failure there is the stale-state bug,
whatever the menu does.

To prove the mechanism instead of inferring it, the CI host can report what UIKit sees. Wrap a `UITextView` in
`UIViewRepresentable` and publish `markedTextRange != nil` and `selectedRange` as the accessibility value of a
small label. Then the test reads "marked=yes sel={4,2}" at each step. Add a second host screen with a `WKWebView`
showing a `contenteditable` div: WebKit is where the 66 pt rule is in the source, and it stands in for Gmail on the
web and in-app browsers. Both are CI host changes for the tower. They are not made here.

## 5. Open questions

- Does UIKit present the edit menu for a range selection while a keyboard extension's marked text is open (H2)?
  Only S3 answers this.
- After `viewWillDisappear`, does the host keep the word *marked*? Sprint 4 item 12 only checked that the half word
  survives hide and reopen (`docs/ios-keyboard-notes.md:218`). If the mark survives, the next word's first
  `setMarkedText` replaces the old half word, and touches near it fail as in H1. The host probe above answers it.
- Does iOS 26 still withhold `textDidChange` / `selectionDidChange` from a keyboard while marked text exists, as
  azooKey saw on iOS 14? Logging both callbacks in the scenario answers it, and decides whether F1 and F2 can run
  at all before the next key.
