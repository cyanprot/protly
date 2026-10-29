# Security review: iPhone keyboard and ProtlyCore

Campaign 2026-10-29-security-review, Sprint 002. Plan: `docs/plans/2026-10-29-security-review.md`.

Scope: `ios-app/ProtlyCore/**`, `ios-app/Sources/Protly/**`, `ios-app/scripts/**`, and in
`ios-app/Sources/ProtlyKeyboard/`: `ActionClient.swift`, `FieldText.swift`, `Panel.swift`,
`ProtlyActionHandler.swift`, `KeyboardViewController.swift` (action, clipboard and field-reading code only).

## Method

- **Audit:** `silent-failure-hunter` and `code-reviewer` checked the files against the plan's threat model.
  `test-strategist` then looked for test gaps in ProtlyCore. All three ran again on the finished diff.
- **Fixes:** every MEDIUM finding and most LOW ones have a fix with a test that failed first. Mutation runs
  showed the fix tests fail without their fixes.
- **Where it ran:** ProtlyCore tests ran on Linux with Swift 6.4.1 (the official `swift:6.4.1-noble` image;
  download.swift.org is blocked from the cloud session).
- **Keyboard target:** it cannot compile here.
  - `ActionClient.swift` was type-checked on Linux against ProtlyCore with a stub `Secrets`. One part is
    unchecked: `URLSession.bytes(for:)` does not exist on Linux, so a shim of the same shape stood in for it.
  - The `KeyboardViewController.swift` changes are listed below for the tower to check on the phone.
- **Source rules:** a ProtlyCore test (`KeyboardSourceRulesTests`) reads the keyboard sources, never
  `Secrets.swift`, and checks code only (comments are blanked). It fails if they log anything, read the
  pasteboard string outside `readClipboard`, use `Secrets` anywhere but `ActionAPI.request`, or call
  `set`/`setValue` on `UserDefaults` (or a name bound to it) for anything but the change count and the
  language. It also fails on any `@AppStorage`.

## What was already sound

- **Key flow:** `Secrets.apiKey` has one use. `ActionClient` passes it to `ActionAPI.request`, which puts it
  in the `x-api-key` header only. Tests check the URL, the other headers and the body.
- **Errors:** nothing in scope logs (`print`, `NSLog`, `os_log`, `Logger`). Every error shown is a fixed
  English line from `ActionError.message`; no response body or request text reaches the UI.
- **Display:** the panel shows text verbatim through `Text(String)`: no Markdown, no links.
- **Request body:** the prompt text goes in as a JSON value, so quotes, control characters and fake JSON are
  escaped.
- **Clipboard:** the pasteboard string is read only in `readClipboard`, and only taps reach it (the bar's
  Read clipboard, the protly key on an empty field, Retry). `refreshField` uses only `changeCount` and
  `hasStrings`, which never show the Allow Paste prompt. `UserDefaults` holds only the change count and the
  last word's language.
- **Field read:** `FieldText.read` always ends (at most 10 jumps × 50 polls × 20 ms) and stops on cancel. A
  read that stops before the end of the field is refused ("Could not read the whole text").
- **Reply parsing:** `JSONSerialization` refuses invalid bytes and deep nesting (the limit of 512 was seen on
  Linux; Darwin's own parser is the tower's test run). UTF-16 bodies are accepted. `parse` maps every
  failure to `.parse`.
- **`make-secrets.sh`:** `umask 077` gives mode 600. The key regex rules out quoting problems in the Swift
  literal. `printf` is a builtin, so the key never shows in `ps`. Nothing secret is printed.

## Findings

| id | severity | where | finding | status |
|----|----------|-------|---------|--------|
| F1 | MEDIUM | `ActionAPI.swift` `body`, `KeyboardViewController.swift` `readClipboard`/`act` | Field, selection and clipboard text went to the API at any length. A multi-MB clipboard took several copies of memory in the keyboard and a large bill, for a reply that cannot fit 16000 tokens anyway. | fixed `5e15292`: `ActionAPI.request` refuses more than 50,000 UTF-16 units with `.tooLong`, before any request exists |
| F2 | MEDIUM | `ActionClient.swift` | `URLSession.shared` keeps a disk URL cache and a persistent cookie store, so a reply holding the translation of clipboard or field text could reach the keyboard's caches. | fixed `c1bb644`: ephemeral session, no URL cache, no cookie or credential store, requests ignore the local cache |
| F6 | MEDIUM | `KeyboardViewController.swift` `insertResult`, `undoInsert` | Insert and Undo checked only the last 40 characters, then deleted the whole original or inserted text. A paste or cut earlier in the draft while the request ran passed the check, and the deletes removed the wrong text. | fixed `05c7135`: `FieldGuard` requires the text before the cursor to end with all of it; tower check 3 |
| F3 | LOW | `ActionClient.swift` | `timeoutInterval` is an idle timeout: a reply dribbled byte by byte never ended. The body was read into memory at any size. | fixed `8681fc7`, `9ec001a`, `52af7d6`, and the last review commit: 90 s cap on the whole request; `ActionAPI.collect` reads at most 2 MB and stops on cancel; the download is cancelled on every way out; `parse` refuses larger |
| F4 | LOW | `Hangul.swift` `Composer` | A raw compound-final key (ㄳ) followed by a vowel trapped on a force unwrap. Not reachable from the keyboard (it feeds only a-z), but the API is public. | fixed `039cbab` |
| F5 | LOW | `Keys.swift` `latin` | `Character("ß".uppercased())` trapped: some letters uppercase to two characters. Same reachability as F4. | fixed `7d60cc0` |
| F7 | LOW | `ActionClient.swift` | An empty key (the CI and cloud stand-in) still sent the user's text. A missing prompt read "The API rejected the request" although nothing was sent. | fixed `5717977`: `.noKey` and `.setup`, no request |
| F8 | LOW | `ActionClient.swift` | URLSession follows redirects and replays all headers, `x-api-key` included, to the new URL. Only the API could send one, over TLS. | fixed `e225e46`, `9ec001a`: `ActionSessionDelegate` refuses every redirect; tower check 1 |
| F9 | LOW | `ActionAPI.swift` `mode(forDraft:)` | Decomposed (NFD) and halfwidth Korean were sent to Polish as an English draft. | fixed `54cf0db` |
| F10 | LOW | `KeyboardViewController.swift` `act` | The Full Access path and Read clipboard's own failures (nothing copied, paste not allowed) did not cancel a running Translate/Polish, whose result later replaced their panel. A successful clipboard read already cancelled it. | fixed `62e2f5c`; tower check 6 |
| F11 | LOW | `make-secrets.sh` | The key was written before the gitignore check; the key file's mode was never checked. | fixed `5b9b8fc`, `9ec001a`: check first, warn on a readable key file (through a symlink too); tower check 8 |
| F17 | LOW | `TypingSession.swift` `flip` | The flip deleted `text.count + after.count`, but in the field the word and what follows it can join into one character (a combining mark, a final jamo, the second half of a flag), so it deleted a character before the word. | fixed `4c0177f` |
| F18 | LOW | `TypingSession.swift` `backspace` | A backspace with nothing being typed left the committed word flippable although the keyboard then deleted normally (safe today only because the controller also forgets it). | fixed `4c0177f` |
| F19 | LOW | `WordList.swift` `init` | A count near `Int.max` trapped on overflow; negative counts could make the score NaN. | fixed `64f9500`: counts saturate, below 1 dropped |
| F20 | LOW | `WordList.swift` `parse` | `"\r\n"` is one Character, so a CRLF list loaded nothing and the detector silently called common English words Korean. The bundled lists have no CR. | fixed `64f9500`; both bundled lists load the same 46,717 and 49,314 keys as before, and a test fails if either drops below 40,000 |
| F21 | LOW | `ActionAPI.request` | A blank key, or one holding CR, LF, NUL or non-ASCII, still built a request; URLRequest drops such a header value, so the text went out with no key. | fixed `c08d382` |
| F22 | LOW | `ActionAPI.swift` `mode(forDraft:)` | The Hangul fillers (U+115F, U+1160, U+3164, U+FFA0) are invisible and pasted as spacers on Instagram; an English draft holding one was offered Translate. | fixed `3a644d0` |
| F12 | LOW | `FieldText.replace`, `undoInsert`, flip | Deletes count Swift characters (grapheme clusters). A host whose `deleteBackward` removes less (combining marks, some emoji sequences, `\r\n`, NFD Hangul) would leave characters behind. | reported, tower checks 9 and 11 |
| F13 | LOW | `TypingSession.swift` | Each key recomposes and re-detects the whole word (O(n²) per word: 1,200 keys without a space took 9.5 s in a Linux debug build), and `last.after` grows with every non-letter insert. Both are bounded by human typing; no trap. | reported, Q5 |
| F14 | LOW | `ActionAPI.kind(status:body:)` | Every 400 shows one line and 403 says the key was rejected, whatever the cause (low balance, prompt too long, workspace mismatch). No body is shown, which is right. | reported |
| F15 | LOW | `KeyboardViewController.swift` (detector load, view lifecycle) | `try? LanguageDetector.bundled()` leaves the Hangul-only rule in place silently for the life of the process if the word lists fail to load. | reported (view lifecycle belongs to the layout campaign) |
| F16 | LOW | `KeyboardViewController.swift` `readClipboard` | A clipboard holding an empty string shows "Paste was not allowed." instead of "Copy a message first." | reported (UI text) |
| F23 | LOW | `KeyboardViewController.swift` `undoInsert` | Since F6 Undo needs all of the inserted text before the cursor. When it does not match, the Undo button just goes away, with no message. A host that cuts the text before the cursor short (at a paragraph break or a size limit) would lose Undo after a long insert. It fails safe. | reported, tower check 3 |
| F24 | LOW | `ActionAPI.parse`, `ActionClient` | An error reply over 2 MB (401, 429, 5xx) shows "The reply was not readable" instead of its own message. | reported (cosmetic) |

## Questions for the tower

- **Q1, key embedding:** the key is a plain string in the keyboard binary; anyone with the app bundle can
  extract it. Is it a dedicated key, in its own workspace, with a spend limit (the code already handles
  `enforced_spend_limit_reached`)? Is it kept separate from the extension's host key, with a rotation plan?
- **Q2, prompt injection:** someone else's message on the clipboard can steer the model, for example to make
  the Korean reading of a scam look harmless. Output is shown, never executed, and `.in` offers no Insert. A
  "treat TEXT as data" line belongs in `ios/keyboard-prompt.txt`, which this sprint does not edit.
- **Q3, input cap:** 50,000 UTF-16 units rejects only text whose reply cannot fit 16000 tokens. A lower cap
  (for example 20,000) would also limit the bill per tap. Which number?
- **Q4, billing:** a client timeout (30 s idle) on a non-streaming request is still billed, and Retry bills
  again. Should a timeout say so, or should the request stream?
- **Q5, flip reach:** `TypingSession.noteInserted` keeps growing `last.after` (spaces, punctuation, emoji, a
  newline) until the next letter, so the bar's flip can reach back over a long insert. Should it reach over
  whitespace only?
- **Q6, script test:** `make-secrets.sh` was checked by hand in a scratch clone. An offline node test needs a
  file in `tests/**`, which belongs to Sprint 001: a temp git repo, a fake key, not-ignored refused,
  mode 600, the warning, and the key never in the output. Add it there?

## Changes

- ProtlyCore `ActionAPI`:
  - `request(mode:text:system:apiKey:)` builds the `URLRequest`: no cache, no cookies, 30 s idle timeout.
    It refuses:
    - a missing key, or one that is not printable ASCII without spaces (`.noKey`);
    - an over-long text (`.tooLong`);
    - a body that cannot be built (`.setup`).
  - `sessionConfiguration()`: ephemeral, no cache, no cookie or credential store, 90 s total.
  - `ActionSessionDelegate` refuses redirects.
  - `collect(_:limit:)` reads the reply up to `maxResponseBytes` (2 MB) and stops on cancel; `parse` refuses
    a larger body.
  - `mode(forDraft:)` knows every Hangul block except the invisible fillers.
  - ProtlyCore imports FoundationNetworking on Linux only (`#if canImport`).
- ProtlyCore `FieldGuard`: the whole-text checks for Insert and Undo.
- ProtlyCore `Hangul`, `Keys`: no traps on odd keys.
- ProtlyCore `TypingSession`: the flip counts the word and what follows together; a nil backspace ends the
  flip.
- ProtlyCore `WordList`: counts saturate; lines split on any line break and fields on any whitespace.
- `ActionClient`:
  - uses `ActionAPI.request`, and one session built from `sessionConfiguration()` with the redirect delegate;
  - reads the reply through `bytes(for:)` and `ActionAPI.collect`, and cancels the download on every way out.
- `KeyboardViewController`: Insert and Undo call `FieldGuard`; `act` cancels a running action first.
- `make-secrets.sh`: the gitignore check runs before writing; a readable key file gets a warning.
- New tests (49 → 95 ProtlyCore tests):
  - `ActionRequestTests`: key placement, escaping, limits, timeouts, no disk, no redirects, `collect`.
  - `ActionAPIHostileTests`: malformed and hostile replies.
  - `FieldGuardTests`.
  - `UnicodeRobustnessTests`: odd keys, very long input, every Hangul form, flip counts, word lists.
  - `KeyboardSourceRulesTests`.

## Phone checks for the tower

1. `xtool dev build` compiles cleanly:
   - The reply loop in `ActionClient` (`bytes(for:)`, `ActionAPI.collect`, `bytes.task.cancel()`) compiles.
     Linux could check it only against a shim.
   - No warning that `ActionSessionDelegate`'s redirect method "nearly matches" an optional requirement. If
     that warning appears, the delegate is not called and F8 is not fixed.
   - Also run `swift test --package-path ios-app/ProtlyCore` on the Mac: some parser tests take either a
     value or `.parse`, because Darwin's JSONSerialization differs from Linux's.
2. Translate, Polish and Read clipboard work as before in Messages, Instagram and Gmail, and Cancel during
   loading still stops the request.
3. Insert and Undo (F6, F23):
   - In Messages, Instagram and Gmail: Polish a three-paragraph draft, Insert, then Undo. Both work. If
     Undo's button goes away without undoing, that host shortens the text before the cursor; record it in
     `docs/ios-keyboard-notes.md`.
   - Then start a Polish. While it loads, paste a word near the start of the draft with the edit menu, put the
     cursor back at the end and tap Insert. Expect "The text changed. Try again." and an untouched draft.
4. Copy more than 50,000 characters (for example a long web page) and tap Read clipboard. Expect "The text is
   too long. Try a shorter text." and no request in the console usage (F1).
5. In a build with the empty stand-in key, tap Polish. Expect "protly was built without an API key..." and
   nothing sent (F7).
6. Start a Polish, then tap Read clipboard with nothing copied. The panel stays on "Copy a message first."
   (F10).
7. A draft in NFD Korean (a file name copied from Finder) offers Translate, not Polish (F9).
8. On the laptop, `ios-app/scripts/make-secrets.sh` still writes `Secrets.swift` with mode 600. After
   `chmod 644 ~/.config/protly/phone-api-key` it warns (F11; restore 600 afterwards).
9. Insert and Undo over a draft containing "e" + U+0301, 👨‍👩‍👧, 🇰🇷 and a pasted Windows line break
   leave no stray characters (F12).
10. Clearing a mark (`apply(.mark(""))`) deletes `marked.count` characters after inserting the mark. This
    sprint did not change it (typing code, outside its files). The mark holds only a-z or jamo today, so it
    cannot join the character before it. Check that clearing a mark at the start of a word typed right after
    an emoji or an accented letter leaves that character intact.
11. Insert and Undo with a translation that contains NUL or U+2028 (both pass through `parse` unchanged):
    what does `insertText` do with them? Over an NFD Korean draft, does `deleteBackward` remove a whole
    syllable per call, as the counts (and `FieldGuardTests`' NFC/NFD case) assume? If it removes one jamo per
    call, `FieldGuard` must compare scalars.
12. Optional, after a few actions: the keyboard extension's container has no `Caches/*/Cache.db` holding
    replies and no cookie file for api.anthropic.com (F2; needs the device container from Xcode).
