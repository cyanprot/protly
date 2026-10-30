# The composing underline is invisible on dark screens

Research only, 2026-10-30. No code, test or workflow was changed. One throwaway script ran locally, outside the
repo; its key code is quoted in section 5.

## The report

The owner uses Protly every day. Sometimes, while a word is being typed and is underlined, it cannot be seen on a
black or dark screen.

## Summary

- **Every word Protly types is marked text until it is committed.** This includes English words, and the whole
  word is marked, not only the Hangul syllable being composed. The host app draws marked text and chooses its
  style. A keyboard extension can only pass a string and a range.
- **Apple's Korean keyboard does not use marked text on iOS.** `markedTextRange` stays nil while it composes
  Hangul, and an Apple engineer confirmed this. Web pages see it as `deleteContentBackward` + `insertText`. So a
  host whose marked-text drawing is broken in dark mode never shows that bug with Apple's keyboard. It shows it
  only with Protly. That fits a report that says "sometimes".
- **The simulator shots cannot reproduce it.** In `runs/e301e04-15`, dark mode, the CI host draws the composing
  word in the field's own white, with a 2 pt underline in the cursor's (tint) color. The host's background is a
  fixed green, so the test cannot show a dark host. WebKit's source draws the underline in system blue and the text
  in the page's color, which is also visible. Invisibility therefore depends on the host: a host that draws marked
  text in a fixed or default color, or a tint near its background color. Which hosts do this is not measured yet.
- **Recommendation: stop using marked text.** Insert the word as plain text and change it by deleting and retyping
  only the changed tail. This is what Apple's Korean keyboard does. `TypingSession` stays as it is. One pure diff
  function goes into ProtlyCore, and `apply` in `KeyboardViewController.swift` changes. The same change removes the
  live marked text that the sibling reports on Return and on the edit menu depend on.

## 1. What the owner sees

### 1.1 What Protly sends

- `TypingSession.type` returns `.mark(word)` for every key, Korean or English
  (`ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift:56-61`). Backspace inside a word does the same
  (`:64-77`). A flip while typing does the same too (`:130-135`).
- `apply(.mark(text))` calls `proxy.setMarkedText(text, selectedRange: end)`
  (`ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift:193-195`). So the whole word stays marked (and
  underlined) until a space, punctuation, Return, a cursor move or a bar action commits it
  (`KeyboardViewController.swift:177-181`, `:378-415`, `TypingSession.swift:80-92`).
- The commit is `setMarkedText("")` followed by `insertText(word)` (`KeyboardViewController.swift:196-200`).
  Clearing the last jamo uses a workaround: settle it as text, then delete it, because "Clearing a mark makes hosts
  swallow the next delete" (`:187-192`).
- So the last word of a message is underlined whenever the user stops typing before a space. That is the usual
  state just before Send.

### 1.2 Text or underline, and in which hosts

The report says "it" is invisible while underlined. That reads as the word itself. The evidence so far:

| Host | Evidence | Composing word | Underline |
|---|---|---|---|
| CI host (SwiftUI `TextField`, UIKit), dark mode | `ci-shots` `runs/e301e04-15`, measured below | visible, field color white | visible, tint blue, 2 pt |
| Safari, Chrome, any `WKWebView` (iOS 17+) | WebKit source, section 2.2 | page's own text color | system blue (black on the old path, section 2.2) |
| Instagram DM, KakaoTalk, Messages | phone, Sprint 2 item 4: "Underline visible while composing" (`docs/ios-keyboard-notes.md:115`); Sprint 4 item 20, Instagram DM in dark mode: "English underline: acceptable" (`:223`) | seen at least once | seen at least once |
| Other fields in those apps (story replies, comment boxes over photos), other apps | not measured | unknown | unknown |

So at least one Instagram DM field drew both the word and the underline in dark mode. The report's "sometimes"
then points to particular fields or apps, not to dark mode as a whole. Two questions for the owner settle 1.2: (a)
is the letters' color wrong or missing, or only the line under them? (b) which app and which screen? A screenshot
while the word is underlined is enough.

### 1.3 The simulator shots (`ci-shots`, `runs/e301e04-15`)

Setup: iOS 26.5 simulator, iPhone 13 Pro, `appearance dark` (`runs/e301e04-15/report.txt`, set by
`ios-app/CI/run-shots.sh:101`). The host is one SwiftUI `TextField(axis: .vertical)` on solid green
`(32, 160, 96)`, with its text forced to white (`ios-app/CI/Host/HostApp.swift:21-27`). It sets no tint.

The full-screen shots `06-word-typed.png` and `c-<id>.png` are taken after the word is committed (`hello ` is
typed with a space, `ios-app/CI/UITests/KeyboardShotsUITests.swift:46-47`). They show no underline. The bar-reading
shots are taken while a word is still being typed:

| Shot | Field | What it shows (pixels in the 1170 x 2532 PNG) |
|---|---|---|
| `c-6.8-4-1-right.png` | `안녀` (composing) | glyphs `(255, 255, 255)`; a 6 px (2 pt) underline at y 270-275, x 49-135, color `(0, 145, 255)` |
| `c-6.8-3-1-right.png` | `tomo` (composing, English) | the same white glyphs; underline x 49-168, `(0, 145, 255)`; the caret column is the same `(0, 145, 255)` |
| `c-8.5-8o-1-center.png` | `…늦으면 미안 ㅠㅠ` (cursor after `ㅠㅠ`) | only `ㅠㅠ` is underlined (y 397-402), in `(0, 145, 255)` |

Measured with PIL on the PNGs fetched from `origin/ci-shots` (commit `5724014`). Conclusions:

- In a UIKit field, marked text keeps the field's own text color. The underline uses the same color as the caret,
  which is the host's tint (here SwiftUI's default accent).
- The English word `tomo` is underlined like the Korean one (1.1).
- The CI host cannot show the report. Its background is green, not black, and the white text color is set
  explicitly. A host that leaves the text color to UIKit, or draws marked text itself, is not covered.

## 2. Who draws marked text

### 2.1 The keyboard has no say

- `UITextDocumentProxy` offers `setMarkedText(_:selectedRange:)` and `unmarkText()` and nothing about style
  (https://developer.apple.com/documentation/uikit/uitextdocumentproxy). `setMarkedText` "Inserts the provided text
  and marks it to indicate that it's part of an active input session" and takes only a `String` and an `NSRange`
  (https://developer.apple.com/documentation/uikit/uitextdocumentproxy/setmarkedtext(_:selectedrange:)). There is
  no attributed variant for keyboard extensions.
- The style is the host's: `UITextInput.markedTextStyle` is "A dictionary of attributes that describes how to draw
  marked text", set on the host's text view
  (https://developer.apple.com/documentation/uikit/uitextinput/markedtextstyle). A custom text engine that adopts
  `UITextInput` (Flutter, React Native wrappers, chat apps with their own composer, games) draws marked text itself.
- React Native's text input shows that hosts treat marked text as a separate styling state. It skips reapplying its
  own attributes while `markedTextRange` is set or the input mode is `ko-KR`: "when the user is in the middle of
  inputting some text in Japanese/Chinese, there will be styling on the text that we should disregard … updating
  the attributed text while inputting Korean language will break input mechanism"
  (https://github.com/facebook/react-native/blob/97f6997ee347f9e406787da9c97fde687cebdda1/packages/react-native/React/Fabric/Mounting/ComponentViews/TextInput/RCTTextInputComponentView.mm#L940-L966).
  Protly reports `primaryLanguage` `ko-KR` (`KeyboardViewController.swift:47-50`), so such hosts take that path for
  Protly too.

### 2.2 WebKit (Safari, Chrome, in-app browsers)

All iOS browsers use WebKit (https://developer.apple.com/app-store/review/guidelines/#2.5.6). The source below is
WebKit `main` at `0bfa170` (`WK` = https://github.com/WebKit/WebKit/blob/0bfa170d0571846c7d3a954d714ec8cd6365c549).

- `WKContentView` ignores `markedTextStyle`. The getter returns nil and the setter is empty
  (`WK/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm#L6612-L6619`).
- Plain `setMarkedText:selectedRange:` adds one underline over the whole mark with the given color `black`
  (`#L6756-L6765`). `setAttributedMarkedText:` does the same unless UIKit passes foreground or background colors,
  in which case it uses those as highlights (`#L6622-L6646`, `#L6649-L6677`, `#L6712-L6754`).
- Painting: with the redesigned text cursor (iOS 17 and later), the underline is drawn in `AppleSystemBlue` in the
  system appearance. The given black only switches it on (`WK/Source/WebCore/rendering/TextBoxPainter.cpp#L1383-L1403`).
  Without the redesigned cursor it is a 1 px line in the given color, black (`#L1355-L1380`). That is invisible on
  a dark page. WebKit fixed this for macOS and GTK in 2017 by using the text color
  (https://bugs.webkit.org/show_bug.cgi?id=174675), but the iOS path still passes black.
- The composing text is painted with the page's own style unless highlights are given
  (`TextBoxPainter.cpp#L343-L356`). On a normal dark page the word is visible.
- WebKit honours UIKit's thick-underline segments since 2023 (https://bugs.webkit.org/show_bug.cgi?id=259604,
  https://commits.webkit.org/266401@main). Neither change mentions dark mode.
- One open report says iPadOS 27 Safari "appears to paint the IME marked text (or part of it) using the caret
  color". A page that sets `caret-color: transparent` (CodeMirror's `drawSelection`) then shows invisible
  composition (https://github.com/jmfederico/pi-web/issues/309, unverified by its maintainer). Rich web editors
  that hide the native caret are therefore candidates on the web.

### 2.3 What other keyboards do

- **Apple's Korean keyboard.** It does not use marked text on iOS. A developer found `markedTextRange` "remains nil
  throughout the composition process" with Korean in a `UITextField`. An Apple DTS engineer answered that the
  marked range ends for Chinese and Japanese "but not for Korean"
  (https://developer.apple.com/forums/thread/787069, June 2025). Web pages see each jamo as a `keydown` with key
  code 0, then `deleteContentBackward` + `insertText` and no composition events. This was seen in the iOS 27.0
  simulator in Safari (https://github.com/devswha/herdr-web-ui/pull/1327) and on iPadOS 26.5
  (https://github.com/cuter74-dev/wowTerminal/issues/162). React Native special-cases `ko-KR` next to
  `markedTextRange` for the same reason (2.1). So Apple's keyboard composes by replacing the last character, which
  hosts show as ordinary text.
- **azooKey** (open-source Japanese keyboard). It does not use `setMarkedText` by default. Marked text is an opt-in
  trial setting ("入力中のテキストを保護", 試験版), because tapping marked text made it vanish on several iOS
  versions (https://zenn.dev/en3_hcl/articles/96c2d043fdaeac). Its earlier survey found WebKit fields give
  "全く違う結果" (completely different results) (https://zenn.dev/azookey/articles/896fb7b52bf13b).
- **Gboard.** I found no public source on whether Gboard for iOS marks Korean text. This is not verified.
- **Apple Developer Forums, iOS 27 beta.** Marked text from a keyboard extension "will be disappear" when touched
  or when the cursor moves into it (https://developer.apple.com/forums/thread/833053). If that happens on a dark
  screen, it can look like the same symptom.

## 3. Likely causes, ranked

None of these can be confirmed without the owner's answer (1.2) or the scenario in 4.3. They share one
precondition: live marked text. Apple's Korean keyboard never creates it (2.3).

1. **The host draws marked text in a color that does not follow dark mode** (the word is invisible). This applies
   to a custom `UITextInput` engine or an attributed composer that styles committed text itself and leaves marked
   text at the default attributes (black) or at a fixed `markedTextStyle`. Once committed, the app restyles the
   word, so it shows "only while underlined". Plausible for app-specific fields; not yet tied to a named app.
2. **The underline is drawn in a tint close to the background** (only the line is invisible). UIKit uses the
   field's tint (1.3). A dark-themed app with a dark or black tint hides it. WebKit without the redesigned cursor
   draws it black (2.2).
3. **The marked text vanishes** (forum 833053, azooKey) after a touch near the word. The owner may connect this
   with dark screens because it was noticed there.
4. **Web editors** that hide the native caret (pi-web 309), or render composition themselves.

## 4. Options

| | Option | What changes for the owner | Risks | Code touched |
|---|---|---|---|---|
| A | **No marked text.** Insert the word as plain text. Each key deletes the characters that changed and types the new tail. | No underline, ever. The word looks like committed text, as with Apple's Korean keyboard. The bar still shows the other reading. | Lost or wrong words if the cursor moved: delete only after checking that the field still ends with the word, which is now possible (see below). Host undo steps become per key (Apple's keyboard behaves the same). More proxy calls per key: about 1.75 instead of 1 (section 5). | `apply` and its mirror (`KeyboardViewController.swift:29-33`, `:183-205`), `noticeFieldMoved` (`:156-174`), `typeLetter` (`:116`), `viewWillDisappear` comment (`:101-104`), `textDidChangeAsync` (`:439-443`). One new pure function in ProtlyCore. `TypingSession` unchanged. |
| B | Mark only the Hangul syllable being composed, with the rest of the word plain. | A one-syllable underline in Korean; English words plain. | Keeps every host risk for that syllable (3.1-3.4), including the Return and edit-menu triggers. Mixed plain plus marked edits, flips that cross the boundary, and the `setMarkedText("")` delete quirk (`:187-192`) remain. The hardest to get right. | Everything in A plus a split of each `.mark` into a plain head and a marked tail. |
| C | Keep marked text and accept the host's style. Optionally add a setting (azooKey's opt-in). | Nothing changes; the bug stays in the affected fields. | None new. The Return and edit-menu issues stay at their root. | None, or a toggle. |
| D | Commit after an idle pause (the edit-menu doc's F3). | Underline while typing, gone after about 1-2 s. | The word is invisible exactly while it is typed, which is the reported moment, so this does not fix the report. It splits words at a pause. | `TypingSession` timer state and the keyboard. |

### Risks of A in detail

- **Lost words.** Today a word in progress is excluded from `documentContextBeforeInput`, so Protly guesses field
  changes from `wordStartBefore` (`KeyboardViewController.swift:29-33`, `:156-174`). With plain text the word is in
  the context. Before any delete, Protly checks `before.hasSuffix(written)` and abandons the word if the check
  fails. This is the check the committed-word flip already uses (`lastTail`, `:168`; `TypingSession.swift:44-46`),
  and it passes in the simulator on UIKit for Latin to Hangul (`ws-1`) and Hangul to Latin (`6.8-11`)
  (`docs/ios-keyboard-notes.md:502-506`). Deletes are per character. Precomposed syllables, compatibility jamo and
  ASCII are one grapheme each, which `TypingSession.flip` already counts on (`TypingSession.swift:143-144`).
- **Undo.** Protly's own Undo (`lastInsert`, `FieldGuard.canUndo`) is unaffected; it already ends on any key
  (`KeyboardViewController.swift:114`, `:312-322`). The host's shake-to-undo records small edits instead of one
  marked commit, the same as with Apple's Korean keyboard (2.3).
- **Host autocorrect and spell check.** Hosts do not autocorrect; the keyboard does. A host spell checker may
  briefly underline a partial plain word in red, as it does with Apple's Korean keyboard. Protly turns off
  KeyboardKit's autocap (`:65-66`). `textDidChangeAsync` then no longer needs its composing guard, because the
  context will include the word (`:439-443`).
- **Return** (open PR https://github.com/cyanprot/protly/pull/11, `docs/research/2026-10-30-enter-clears-web.md`
  on its branch). Today Return mid-word is `setMarkedText("")`, `insertText(word)`, `insertText("\n")` in one
  turn. In WebKit, `setMarkedText("")` deletes the composition and fires `compositionend ""`. With A, Return is
  only `insertText("\n")` after plain text, which is what Apple's keyboard sends. It also removes the stale-host-
  composition case, because a host composition never exists.
- **Edit menu** (open PR https://github.com/cyanprot/protly/pull/9, `docs/research/2026-10-30-edit-menu-missing.md`
  on its branch). Its top cause, H1, is live marked text at the moment of the long-press. A has no marked text, and
  that doc's own F4 (mark less) points the same way.
- **Pages that wait for `isComposing`.** "Enter to send" handlers that ignore Enter while composing will now send
  at once. That is the same as Apple's keyboard, which never composes.
- **What the owner loses.** The underline was the only sign of which word the bar's flip will change. The bar
  already shows the other reading (`ProtlyMode.alternative`, `KeyboardViewController.swift:12`, `:358`).

## 5. Recommendation: A, and how to prove it

A fixes the report in every host without knowing which host draws marked text badly. It matches what Apple's Korean
keyboard does, so hosts are already built for it. It removes the shared root of the Return and edit-menu reports.
It also leaves `TypingSession` and its tests as they are: `.mark(word)` keeps meaning "the word is now this", and
only the keyboard's way of writing it changes.

### Shape

```swift
// ProtlyCore: what to send to turn the word Protly last wrote into the new one.
public enum PlainWord {
    /// Delete the characters after the common prefix, then insert the rest of `new`.
    public static func edit(from old: String, to new: String) -> (deleting: Int, inserting: String) {
        let o = Array(old), n = Array(new)
        var i = 0
        while i < o.count, i < n.count, o[i] == n[i] { i += 1 }
        return (o.count - i, String(n[i...]))
    }
}

// KeyboardViewController.apply, sketch: `written` replaces `marked`.
case .mark(let text), .commit(let text):
    guard (proxy.documentContextBeforeInput ?? "").hasSuffix(written) else { abandonWord(); return }
    let e = PlainWord.edit(from: written, to: text)
    for _ in 0..<e.deleting { proxy.deleteBackward() }
    if !e.inserting.isEmpty { proxy.insertText(e.inserting) }
    written = isCommit ? "" : text
```

The proof ran locally as a Python port of `edit`, outside the repo (no Swift toolchain in this container). It
replayed the `.mark` strings that `TypingSession` returns key by key (the sequences as in
`TypingSessionTests.swift`):

```
안녕하세요 (dkssudgktpdy): every key deletes at most 1 character; 21 proxy calls for 12 keys
  '안녕핫' -> '안녕하세': deleteBackward x1, insertText('하세')
hello after Korean (ㅗ, ㅗㄷ, hel, hell, hello): the switch to English rewrites the word once
  'ㅗㄷ' -> 'hel': deleteBackward x2, insertText('hel'); 7 calls for 5 keys
backspace 안녕 -> "": deleteBackward x1 (+ insertText) per key; no settle-and-delete dance
```

### Unit tests (ProtlyCore, `swift test --package-path ios-app/ProtlyCore`)

- `PlainWord.edit`: `("", "ㅇ")` -> `(0, "ㅇ")`; `("안녕핫", "안녕하세")` -> `(1, "하세")`; `("ㅗㄷ", "hel")` ->
  `(2, "hel")`; `("안", "")` -> `(1, "")`; equal strings -> `(0, "")`; `("ㅋㅋ", "ㅋㅋㅋ")` -> `(0, "ㅋ")`.
- Replay property: for every key sequence in `TypingSessionTests` and the eval's chat corpus, applying each edit to a
  string model of the field (a `FakeField` that deletes Characters and appends) gives exactly the `.mark` text after
  each key and the `.commit` text at the end. The same holds after `backspace()`, `flip()` while typing, and
  `accept()`.
- Deletes never exceed the previous word's length (no edit reaches text before the word).
- A source-rule test in the style of `KeyboardSourceRulesTests.swift` that fails if `setMarkedText` or
  `unmarkText` appears in `ios-app/Sources/ProtlyKeyboard`.

### Simulator scenario (keyboard-shots CI, planned by the tower)

The current CI host cannot show the bug (1.3), so the scenario needs more host fields. That means changes to
`ios-app/CI`, which is out of scope here.

1. **Before the fix, reproduce the report.** Add fields to the CI host that stand in for the suspect hosts: (a) a
   `UITextView` on black whose text color comes only from `attributedText` (no `textColor`, no
   `typingAttributes`); (b) a `UITextField` on black with a near-black `tintColor`; (c) a `WKWebView` page with
   `color-scheme: dark`, black background and `caret-color: transparent`. Type `dkssud` and `tomo` without a
   space, screenshot, and record the glyph-pixel count and underline color inside the field's frame (measure.py
   style). A field whose word has no glyph ink while marked, but does after a space, reproduces cause 1. Record
   all three, so the doc's ranking is tested rather than assumed.
2. **After the fix, in every field:** the word's glyph ink while typing equals its ink after a space (same color),
   and no underline pixels appear. The XCUITest field value after each key equals the `.mark` text (`안`, `안ㄴ`,
   `안녀`, …). Backspace inside `안녕` gives `안녀`. A flip while typing gives the other reading with nothing left
   behind. Return after `안녕` with no space gives `안녕\n` (UIKit) and keeps the page's text (WebKit; the Return
   doc's scenario). A long-press right after the word shows Copy (the edit-menu doc's S1).
3. The existing checks must still pass unchanged (`6.8-1` to `6.8-11`, `ws-1` to `ws-3`, `8.5-*`), plus Sprint 4
   item 12 (half word survives hide and reopen), which becomes trivial because the word is already plain.

On the phone (tower): the owner's own app and screen from 1.2, before and after.

## Sources

- Code: `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`,
  `ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift`, `ios-app/CI/Host/HostApp.swift`, at `main` `1624fcc`.
- Screenshots: `origin/ci-shots` `5724014`, `runs/e301e04-15/`.
- Apple: https://developer.apple.com/documentation/uikit/uitextdocumentproxy,
  https://developer.apple.com/documentation/uikit/uitextdocumentproxy/setmarkedtext(_:selectedrange:),
  https://developer.apple.com/documentation/uikit/uitextinput/markedtextstyle,
  https://developer.apple.com/forums/thread/787069, https://developer.apple.com/forums/thread/833053,
  https://developer.apple.com/app-store/review/guidelines/#2.5.6.
- WebKit: https://github.com/WebKit/WebKit/blob/0bfa170d0571846c7d3a954d714ec8cd6365c549/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm,
  https://github.com/WebKit/WebKit/blob/0bfa170d0571846c7d3a954d714ec8cd6365c549/Source/WebCore/rendering/TextBoxPainter.cpp,
  https://bugs.webkit.org/show_bug.cgi?id=174675, https://bugs.webkit.org/show_bug.cgi?id=259604,
  https://commits.webkit.org/266401@main.
- Others: https://github.com/facebook/react-native/blob/97f6997ee347f9e406787da9c97fde687cebdda1/packages/react-native/React/Fabric/Mounting/ComponentViews/TextInput/RCTTextInputComponentView.mm#L940-L966,
  https://github.com/devswha/herdr-web-ui/pull/1327, https://github.com/cuter74-dev/wowTerminal/issues/162,
  https://zenn.dev/azookey/articles/896fb7b52bf13b, https://zenn.dev/en3_hcl/articles/96c2d043fdaeac,
  https://github.com/jmfederico/pi-web/issues/309.
