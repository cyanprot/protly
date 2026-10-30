# Return clears the message in Safari and Chrome

Research only, 2026-10-30. No code, test or workflow was changed. The one experiment below ran in local Chromium,
outside the repo; its key code is quoted here.

## The report

The owner uses Protly every day. Sometimes, in Safari or Chrome on the iPhone, pressing Return makes the typed
message disappear. It is not a mistaken tap. It happens in web pages, not in every app.

Chrome on the iPhone uses the same engine as Safari: App Review Guideline 2.5.6 requires apps that browse the web to
use WebKit (https://developer.apple.com/app-store/review/guidelines/#2.5.6). So the bug lives where Protly meets
WebKit's text input (`WKContentView`) and the page's JavaScript, not in either browser alone.

Sources pinned for this note:

- WebKit `main` at `aaf9552` (`WK` below = https://github.com/WebKit/WebKit/blob/aaf9552badcbd9cc58f3bc39227db3d864833067).
- WebKit release branch `safari-7623-branch` at `fcddc1c` (`WK7623` = https://github.com/WebKit/WebKit/blob/fcddc1c2a26648ce3f8df1e885962d7cee0f7367).
  `insertTextAsync` has moved out of `WebPage.cpp` on `main`, so it is cited from this branch.
- prosemirror-view `master` at `ca4c78e` (`PM` = https://github.com/ProseMirror/prosemirror-view/blob/ca4c78e9b56f1b164c0b3758b59d8748f11b7534).
- Lexical `main` at `545003a` (`LX` = https://github.com/facebook/lexical/blob/545003a47fffa194822f04f1d5c2d7c36c788d8e).

## 1. What Protly does on Return

### The call chain

1. KeyboardKit's button sends `handle(.release, on: .primary(type))` to `ProtlyActionHandler.handle`
   (`ios-app/Sources/ProtlyKeyboard/ProtlyActionHandler.swift:9-34`). `handleInWord` only takes letters and
   backspace (`ProtlyActionHandler.swift:38-53`), so Return goes to `super.handle`.
2. `StandardActionHandler.handle(_:on:replaced:)`
   (`ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Actions/Services/KeyboardAction+StandardActionHandler.swift:216-236`)
   runs the autocomplete hooks, then the gesture action, then case, type and autocomplete updates.
   - `tryApplyAutocorrectSuggestion` (`:466-476`) would apply for `.primary(.return)` and `.primary(.newLine)`
     (`.../Actions/KeyboardAction+Autocomplete.swift:14-18`, `.../_Keyboard/Models/Keyboard+ReturnKeyType.swift:90-96`),
     but there is never a suggestion to apply: Protly never sets a KeyboardKit autocomplete service, and the default
     is `.disabled` (`.../_Keyboard/Keyboard+Services.swift:56`; `grep autocomplete ios-app/Sources` finds only a
     toolbar style, `KeyboardViewController.swift:499`). The "remove inserted space" hooks only match characters
     (`KeyboardAction+Autocomplete.swift:24-31`). So KeyboardKit adds no edit of its own on Return.
3. The gesture action of every `.primary` key is `insertText(.newline)`
   (`.../Actions/KeyboardAction+Actions.swift:72`; `.newline` is `"\n"`, `.../Extensions/String+Characters.swift:17`).
   The return key's label follows the field's `returnKeyType` (`.../_Keyboard/KeyboardContext.swift:295-300`), so
   in a web form it reads `go` or `search`, but it still sends `"\n"`.
4. Protly overrides `insertText` (`ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift:378-384`):

   ```swift
   override func insertText(_ text: String) {
       commitWord()             // :177-181, only when session.isComposing
       super.insertText(text)   // KeyboardKit: textDocumentProxy.insertText("\n")
       session.noteInserted(text)
       endUndo()
       refreshMode()
   }
   ```

5. `commitWord` asks ProtlyCore for the edit (`TypingSession.commit`, `ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift:80-92`):
   `.commit(word)` while a word is being typed, `nil` otherwise. `apply(.commit)`
   (`KeyboardViewController.swift:196-200`) is:

   ```swift
   // unmarkText() followed by another edit in the same run-loop turn loses the word in every host tested.
   proxy.setMarkedText("", selectedRange: none)
   proxy.insertText(text)
   marked = ""
   ```

So **Return while a word is being typed sends three proxy calls in one run-loop turn**:

```
setMarkedText("", {0,0})   // remove the marked word
insertText("안녕")          // put it back as plain text
insertText("\n")           // Return
```

and **Return when no word is being typed sends only `insertText("\n")`**, whatever the host field still holds.

Every word Protly types is marked text until it is committed, English words too: `TypingSession.type` always
returns `.mark` (`TypingSession.swift:56-61`), and `apply(.mark)` calls `setMarkedText`
(`KeyboardViewController.swift:193-195`). A message whose last word is followed directly by Return (the usual way to
end a chat line) always takes the three-call path.

### Bookkeeping that decides which path runs

- `session.isComposing` is `!keys.isEmpty` (`TypingSession.swift:33`). It becomes false without any field edit in
  `TypingSession.abandon()` (`TypingSession.swift:118-124`), called from:
  - `noticeFieldMoved()` (`KeyboardViewController.swift:156-174`) on every `textDidChange` and `selectionDidChange`
    (`:427-437`), and at the start of `typeLetter` (`:115`), `flipWord` (`:138`) and `pickSuggestion` (`:148`). It
    abandons the word when `!p.hasText || before != wordStartBefore` (`:164`), where `wordStartBefore` is the proxy's
    `documentContextBeforeInput` captured at the word's first key (`:116`).
  - `viewWillDisappear` (`:99-109`), with the comment "The host keeps the marked word as text".
- Abandoning clears Protly's mirror `marked = ""` (`:167`, `:104`) but sends nothing to the host: **the host's
  composition, if it still exists, stays live**.
- The Return path does not call `noticeFieldMoved` before `commitWord` (`:378-380`), unlike `flipWord` and
  `pickSuggestion`.

### Bookkeeping that is not involved

- `FieldText.replace` deletes and reinserts the whole field (`ios-app/Sources/ProtlyKeyboard/FieldText.swift:29-36`),
  but only `insertResult` calls it (`KeyboardViewController.swift:305`), from the panel's Insert button.
- `undoInsert` deletes `lastInsert` (`:312-322`); every typing path calls `endUndo` first (`:114`, `:382`).
- `.replace` deletes before inserting (`:201-204`), but only `TypingSession.flip` returns it (`TypingSession.swift:126-145`).
- `.mark("")` settles and deletes the jamo one by one (`:187-192`), but only backspace emits it
  (`TypingSession.swift:64-77`).

None of these runs on Return. The deletions that can happen on Return are all done by WebKit or by the page, as
below.

## 2. How WebKit applies those calls

All verified in WebKit source at the commits above.

| Call | WebKit code | Effect |
|---|---|---|
| `setMarkedText(s, r)` | `WKContentView setMarkedText:selectedRange:` -> `setCompositionAsync` (`WK/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L6756-L6773`, `WK7623/Source/WebKit/WebProcess/WebPage/WebPage.cpp#L7437-L7450`) -> `Editor::setComposition` (`WK/Source/WebCore/editing/Editor.cpp#L2600-L2700`) | `selectComposition()` (`#L2610`) selects the live composition, if any. With `s == ""` it then runs `TypingCommand::deleteSelection` and dispatches `compositionend` **with data `""`** (`#L2668-L2675`). If there is no composition, the current selection is deleted instead: nothing for a caret, **the selected text for a range**. |
| `unmarkText()` | `WKContentViewInteraction.mm#L6775-L6780` -> `Editor::confirmComposition()` (`Editor.cpp#L2363-L2373`) | Keeps the composition text; `compositionend` carries the word. **A no-op when there is no composition** (`if (!m_compositionNode) return;`). |
| `insertText(t)` | `WKContentViewInteraction.mm#L6964-L6999` -> `WebPage::insertTextAsync` (`WK7623/.../WebPage.cpp#L7290-L7327`) | `if (!editor->hasComposition()) insertText(t) else editor->confirmComposition(t)` (`#L7317-L7326`): **while a composition is live, the inserted text replaces it**. The call is dropped while the keyboard hides during a focus change (`#L6966-L6967`). |
| Return from the keyboard | `_internalHandleKeyWebEvent` (`WKContentViewInteraction.mm#L7695-L7736`), `_interpretKeyEvent` (`#L7770-L7840`) | Key events go to the page as `keydown`/`keypress`/`keyup`; in an editable element an unhandled Return becomes `addInputString:@"\n"` (`#L7826-L7832`). Implicit form submission and every "Enter to send" handler hang off these events. |
| `hasText` | `WKContentViewInteraction.mm#L7024-L7032` | `NO` whenever WebKit's latest editor state has no post-layout data, which WebKit sends on purpose right after an edit when layout is pending (`WK/Source/WebKit/WebProcess/WebPage/WebPage.cpp#L8984-L9004`). While a composition is live the state always includes post-layout data (`WK/Source/WebKit/WebProcess/WebPage/ios/WebPageIOS.mm#L325-L334`), and then a field with only marked text counts as having text (`WebPageIOS.mm#L296-L322`): unlike the native hosts in `KeyboardViewController.swift:159`. |
| Composition position | `Editor::compositionRange` (`Editor.cpp#L3750-L3760`), `cancelCompositionIfSelectionIsInvalid` (`#L2432-L2441`) | The composition is a text node plus two offsets. When the page moves the selection out of it, WebKit cancels the composition and **leaves the text in the field** (`#L2480-L2481`). Apple's forum has the keyboard-side view of this: marked text from a keyboard extension "disappears" when the host moves the cursor into it (iOS 27 beta, June 2026, https://developer.apple.com/forums/thread/833053). |

The DOM events a page sees from Protly's Return, replayed in local Chromium (Blink, not WebKit; WebKit's
`Editor::setComposition` above predicts the same order: delete the composition, `compositionend ""`, then a plain
insert):

```js
// throwaway: playwright + CDP, textarea and contenteditable with listeners for composition*, beforeinput, input, key*
for (const s of ['ㅇ','아','안','안ㄴ','안녀','안녕'])
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 }); // setMarkedText("")
await cdp.send('Input.insertText', { text: '안녕' });                                         // insertText(word)
await page.keyboard.press('Enter');                                                          // insertText("\n")
```

```
ms  | event          | data | inputType             | key   | keyCode | isComposing | textarea value
316 | beforeinput    |      | insertCompositionText |       |         | true        | "hello 안녕"
317 | input          |      | insertCompositionText |       |         | true        | "hello "      <- word gone
317 | compositionend | ""   |                       |       |         |             | "hello "
318 | beforeinput    | 안녕 | insertText            |       |         | false       | "hello "
319 | input          | 안녕 | insertText            |       |         | false       | "hello 안녕"  <- word back
322 | keydown        |      |                       | Enter | 13      | false       | "hello 안녕"
```

So a page sees the last word **deleted, the composition cancelled with empty data, the word re-inserted as plain
typing, and Enter about 5 ms after `compositionend`**. Apple's own keyboard and every IME that confirms with
`unmarkText` give `compositionend` with the word as data and no delete. Pages and editors are written for the
second shape.

What the page side does with that shape (verified in source):

- ProseMirror (used by many chat composers) treats a `keydown` within 500 ms of `compositionend` as the IME's
  confirming Enter and **ignores it** when `browser.safari` (`PM/src/input.ts#L435-L451`); `browser.safari` is
  `/Apple Computer/.test(navigator.vendor)`, true for Safari and Chrome on iOS (`PM/src/browser.ts#L17-L19`). On iOS
  it also never handles Enter directly: it waits for the browser's DOM change and then replays Enter through its
  handlers, dropping the DOM change (`PM/src/input.ts#L118-L131`, `PM/src/domchange.ts#L124-L130`, `#L179-L189`).
- Lexical (Meta's web editor) reads `compositionend` with `""` as **a cancellation** and re-reads the text node from
  the DOM (`LX/packages/lexical/src/LexicalEvents.ts#L1939-L1985`, `#L2023-L2035`), then ignores `keydown` while it
  still thinks it is composing (`#L2054-L2059`).
- Hand-written "Enter to send" handlers follow advice like Chrome's IME-safe guide: `preventDefault()` on Enter,
  then return early when `event.isComposing || event.keyCode === 229`, because WebKit delivered `compositionend`
  before the confirming `keydown` (https://developer.chrome.com/docs/modern-web-guidance/guides/forms/ime-safe-enter-submit;
  WebKit bug 165004, macOS, closed in April 2026 as a duplicate of the event-order fix 311717,
  https://bugs.webkit.org/show_bug.cgi?id=165004). Other handlers add a time window after `compositionend`.

Searches for a matching public report (KeyboardKit issues, Apple's forums, Gboard, "custom keyboard Safari return
text disappears", "setMarkedText web view return") found none. The closest are the forum thread above and the
IME-Enter reports already cited.

## 3. Candidate causes, ranked

### C1. Return lands on a composition Protly no longer tracks, and WebKit replaces it with the newline

- **Sequence.** A word is marked in the field. A host callback makes `noticeFieldMoved` abandon it
  (`KeyboardViewController.swift:164-167`) or `viewWillDisappear` runs (`:99-104`): Protly forgets the word and
  sends nothing, but WebKit's composition stays live. Return then takes the short path: `commitWord` does nothing
  (`TypingSession.commit` returns nil, `TypingSession.swift:81`), and `insertText("\n")` reaches
  `insertTextAsync`, which calls `confirmComposition("\n")` because a composition exists
  (`WK7623/.../WebPage.cpp#L7317-L7326`). **The marked word is replaced by the newline.** A one-word message, or
  a message typed as one word (`ㅇㅋ`, `고마워`, `ok`), disappears entirely. A send-on-Enter page then sends the rest
  or nothing.
- **Why web views.** The abandon test compares `documentContextBeforeInput` with the value taken at the word's
  first key. In a web view that context is built from WebKit's editor state, which arrives asynchronously from the
  web process (`WebPage.cpp#L8984-L9004`), and WebKit sends `selectionWillChange`/`selectionDidChange` to the
  keyboard from those updates (`WKContentViewInteraction.mm#L6376-L6413`). If the first key of the last word reads a
  context that does not yet include the previous word's commit and space, a later callback carries the updated
  context, `before != wordStartBefore`, and the live word is abandoned. In native text views the context is
  updated in-process, which is where the rule was tested (Sprint 4, `KeyboardViewController.swift:159`).
- **Also explains** "sometimes": it needs a callback to land after the last key and before Return. A callback in
  the middle of a word would instead show as lost letters while typing (the next key's `setMarkedText` replaces the
  untracked composition), which is worth asking the owner about.
- **Depends on a composing word:** yes, on the host side (marked text live) while Protly's side is not composing.
- **Hosts:** any WKWebView field (Safari, Chrome, in-app browsers). Native fields would lose the word the same way
  if the abandon happened there (UIKit's `insertText` also replaces marked text), but the stale-context trigger is
  web-specific.
- **Verified:** the WebKit half and the Protly half from source. **Not verified:** that Protly actually abandons a
  live word in Safari. The keyboard log in the CI scenario below shows it directly.

### C2. The page handles Enter against a field Protly has just cancelled and rebuilt

- **Sequence.** Return with a word still marked sends the three calls. The page sees the word deleted,
  `compositionend` with `""`, the word re-inserted as plain typing, and `keydown Enter` a few ms later (the table
  above). Editors that keep their own model update it from these events on their own schedule: ProseMirror flushes
  DOM changes after `compositionend` (`PM/src/input.ts#L502-L513`) and, on iOS, replays Enter later and drops the
  DOM change it attributes to Enter (`PM/src/domchange.ts#L124-L130`); Lexical takes `""` as a cancellation. If
  the page's Enter handler sends or splits from a model that does not yet hold the re-inserted word (or treats the
  composition as cancelled), and then re-renders the field from that model or clears it after sending, the text in
  the DOM is lost. An IME guard (`isComposing || keyCode === 229`, or a window after `compositionend`) can instead
  swallow Return entirely after calling `preventDefault()`.
- **Depends on a composing word:** yes. Return after a space (no marked word) sends only the newline and
  should never trigger this.
- **Hosts:** rich-text and framework composers in web pages (chat apps, comment boxes, AI chat sites). Plain
  `<textarea>` and `<input>` fields without scripts keep the text.
- **Verified:** the event shape (Chromium replay; WebKit source predicts the same) and the framework code paths.
  **Not verified:** which page the owner was on, and WebKit's exact `keyCode`/`isComposing` on this `keydown`.

### C3. Return's key event reaches the page before the commit is applied

- **Sequence.** The three calls leave the extension in one run-loop turn and are applied by the host app.
  Protly's own measurements already show the host does not treat same-turn calls as a simple sequence:
  "`unmarkText()` followed by another edit in the same run-loop turn loses the word in every host tested; after
  `setMarkedText("")` hosts swallow the next delete" (`docs/plans/2026-10-28-ios-keyboard.md:1466-1470`). If the
  Enter key event is dispatched while the composition is still live, a send-on-Enter page reads its value
  (a `<textarea>` value includes the marked word; a model-based editor's model does not), sends, and clears the
  field. The late `setMarkedText("")` then finds no composition and `insertText(word)` puts the last word back
  alone into the cleared field; or an `isComposing` guard swallows Return.
- **Depends on a composing word:** yes.
- **Verified:** no. It is a hypothesis about the host bridge, cheap to settle with the event log (does `keydown
  Enter` come before `compositionend`?).

### C4. Return submits a form or the page navigates

- In a single-line `<input>` inside a `<form>`, Enter's `keypress` triggers implicit submission; the key reads `go`
  or `search` because KeyboardKit takes the label from the field (`KeyboardContext.swift:295-300`). A page without
  a script handler reloads or navigates, and the draft is gone. This is the same with Apple's keyboard, so it is a
  confounder to rule out, not a Protly bug.
- **Depends on a composing word:** no.

### C5. `setMarkedText("")` deletes a selected range

- With no live composition, `setComposition("")` deletes the current selection (`Editor.cpp#L2610`, `#L2672`).
  If WebKit has cancelled the composition (the page moved the selection) while Protly still composes, and the page
  left a range selected (typeahead that selects a suggested suffix, select-all after a failed send), Return's
  commit deletes that range. With a caret selection (the usual case) the result is a doubled word instead
  (`안녕안녕`), not a loss.
- **Depends on a composing word:** yes. Least likely: it needs a range selection at that instant.

### Ruled out

KeyboardKit autocorrect and space handling on Return (no autocomplete service, see section 1), `FieldText`,
Undo, flip and the backspace settle loop (none runs on Return).

## 4. Fixes and how to prove them

### Fix options

| # | Change | Fixes | Trade-offs |
|---|---|---|---|
| F1 | When Protly drops a word without editing (`abandon` in `noticeFieldMoved` and `viewWillDisappear`), end the host's composition with `unmarkText()` on the next run-loop turn | C1, C5 | `unmarkText` is a no-op in WebKit when nothing is marked (`Editor.cpp#L2363-L2373`), so it is safe after a sent message. Needs the native hosts re-checked (Sprint 2 table, `docs/ios-keyboard-notes.md:115`), and must not follow another edit in the same turn (the plan's rule above). |
| F2 | Make the abandon rule tolerate a late context: abandon only when the change persists after the next callback, or when the context no longer ends with the text before the word, instead of any inequality | C1 | Smaller change, but a message sent with the keyboard up (the case the rule exists for) is noticed one callback later. |
| F3 | Return while composing: commit the word, then send `"\n"` on the next run-loop turn (`DispatchQueue.main.async`), or after the host's `textDidChange` for the commit (bounded, about 100 ms) | C3, part of C2 | One-turn delay is invisible. Keys pressed in between must queue behind the newline; if the keyboard is dismissed in between, drop the newline. Does not satisfy pages with long windows (ProseMirror's 500 ms), but there it only turns "send" into "newline". |
| F4 | Commit with confirm semantics: `setMarkedText(finalWord)` (when the reading changed), then `unmarkText()`, then the newline on the next turn | C2 (and C3 with F3) | The page sees `compositionend` with the word and no delete, as from Apple's keyboard. This reverses the Sprint 2 decision, so the same-turn loss must be re-measured in every target app. |
| F5 | Re-sync before the Return path: call `noticeFieldMoved()` in the `insertText` override before `commitWord` | consistency only | Same as `flipWord`; harmless, but on its own it does not fix C1 (an abandon still leaves the composition live). |

The likely combination is F1 + F3 (small, local to `KeyboardViewController`), with F4 decided by the event log: if
pages mishandle `compositionend ""`, F4 is the real fix for C2.

### ProtlyCore unit tests

The proxy calls live in `KeyboardViewController.apply` (UIKit), which `swift test` on Linux cannot run. A test
needs the decision moved into ProtlyCore first: a pure planner that turns a `FieldEdit` plus the key (and whether
the host still holds marked text) into proxy operations with explicit run-loop boundaries, and a fake field that
models WebKit's rules from section 2. Sketch:

```swift
enum ProxyOp: Equatable { case setMarked(String), unmark, insert(String), deleteBackward, nextTurn }

/// WebKit's rules: insert replaces a live composition (WebPage::insertTextAsync), setMarked("") deletes the
/// composition or the selected range (Editor::setComposition), unmark keeps the text (Editor::confirmComposition).
struct FakeWebField {
    var text = "", composition: Range<Int>? = nil
    mutating func apply(_ op: ProxyOp) { /* as above, on String indices */ }
}

func testReturnAfterAbandonKeepsTheWord() {
    var field = FakeWebField(text: "hello 안녕", composition: 6..<8)   // host still has 안녕 marked
    var session = TypingSession()                                     // Protly abandoned it: not composing
    for op in ReturnPlan.ops(session: &session, hostHasMarkedText: true) { field.apply(op) }
    XCTAssertEqual(field.text, "hello 안녕\n")                         // today: "hello \n"
}

func testReturnNeverSharesATurnWithTheCommit() {
    var session = TypingSession(); _ = session.type(KeyEvent("d", .none)); _ = session.type(KeyEvent("k", .none))
    let ops = ReturnPlan.ops(session: &session, hostHasMarkedText: true)
    let nl = ops.firstIndex(of: .insert("\n"))!
    XCTAssertTrue(ops[..<nl].contains(.nextTurn))
}
```

`ReturnPlan`, `ProxyOp` and `FakeWebField` do not exist; they are the shape the fix would add.

### Simulator scenario for keyboard-shots CI

The CI host today is one SwiftUI `TextField` (`ios-app/CI/Host/HostApp.swift:14-46`). Add a second screen, chosen
by a launch argument (for example `-web composer`), with a `WKWebView` loading a bundled page (offline, no network):

- four fields: a plain `<textarea>`; an `<input>` in a `<form>` whose `submit` is logged and prevented; a
  `contenteditable` "Enter to send" composer that sends `textContent` on `keydown Enter` (with the common
  `isComposing || keyCode === 229` guard) and clears; optionally the same composer on vendored ProseMirror and
  Lexical builds;
- a logger like the Chromium one above (timestamp, type, `data`, `inputType`, `key`, `keyCode`, `isComposing`,
  value) that posts each line to the host through `window.webkit.messageHandlers.log`, and the host appends it to
  `web-events.txt` in the run folder; a "sent" list shown in a label XCUITest can read.

UI test steps (reusing `Driver.taps(for:)`, `ios-app/CI/UITests/Driver.swift:51-99`, which already types `\n` with
Return), each run in every field:

1. `안녕` then Return at once (word still marked). Expect field `안녕\n` (or sent `안녕`).
2. `hello 안녕` then Return at once. Expect `hello 안녕\n`.
3. Same with a space before Return (no marked word): the control, expected to pass today.
4. Same as 2 with a 300 ms pause before Return (callbacks have landed): the C1 window.
5. One-word `ㅇㅋ` then Return: the whole-message case.

Pass/fail: the field text (or the sent list) is exact; `web-events.txt` records the order of `compositionend`,
`input` and `keydown Enter` and their `keyCode`/`isComposing` (settles C2 and C3), and any `submit` (C4). For C1,
a CI-only debug log in the keyboard (`os_log` of each callback with `hasText`, `documentContextBeforeInput`,
`isComposing` and every abandon), collected with `log collect` from the simulator, shows whether Protly abandoned a
live word before Return. The same page, opened in Safari on the phone, gives the owner a one-minute check on the
real device.
