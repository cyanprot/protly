# protly iOS keyboard: design

Date: 2026-10-28. Status: approved by the user in chat; spec review issues fixed.

> Amended 2026-10-28 by the "Design amendments" section of `docs/plans/2026-10-28-ios-keyboard.md` (no App Group on
> free Apple ID teams, so no settings sharing; Swift 6.4.1 toolchain; measured detector rules). The plan wins where
> they differ.

## Goal

Beat Grammarly's iOS keyboard on the user's own iPhone. protly becomes a custom keyboard that looks and behaves
like Apple's built-in iPhone keyboard, takes no more vertical space, needs no Korean/English keyboard switching,
and puts protly's translate, polish and read actions in the predictive bar and a same-height panel. Nothing busy,
nothing Grammarly-like.

## Why (user pain, 2026-10-28)

- Today the phone runs two Shortcuts ("Protly read", "Protly write") from an AssistiveTouch button. Write mode is a
  copy, trigger, select-all, paste round trip. Read mode is two touches. AssistiveTouch Single-Tap was tried and
  rejected (accidental presses). Back Tap is unused.
- Switching between Apple's Korean and English keyboards with the globe is the single most disliked step. Both
  layouts share key positions, and the user types mostly blind.
- Grammarly's keyboard layout is disliked. The target is Apple's keyboard, identical in look and function.

## Device and constraints

- iPhone 13 Pro (390x844 pt), iOS 27.0.1, no Action Button, no 3D Touch, no Apple Intelligence.
- No Mac. Build on Fedora with xtool (SwiftPM, Xcode 27 SDK built from the .xip), sign with a FREE Apple ID
  (7-day profiles, re-run `xtool dev` or Impactor auto-refresh over USB). Move to the paid program only if the
  project heads toward real distribution.
- The phone has no VPN: the keyboard calls the Anthropic Messages API directly with the user's key.
- Every user-facing string in the app and keyboard is English. Korean appears only on keycaps and in results.
- Repo is local only. Never `git push`.

## Out of scope

- Read mode by screenshot stays the existing `Protly read` Shortcut, untouched.
- Notification auto-translate, the Translate edit-menu provider, AutoFill text insert: not chosen.
- Own emoji panel, QuickPath swipe typing, dictation, Korean autocorrect, next-word prediction.
- Chrome extension: no changes.

## Architecture

New top-level folder `ios-app/`, a SwiftPM package built by xtool:

| Target | Kind | Role |
|---|---|---|
| `ProtlyCore` | library, no UIKit | Hangul composer, language detector, completion and autocorrect, request builder, response parsing. Unit tested on Linux with `swift test`. |
| `ProtlyKeyboard` | keyboard extension (`com.apple.keyboard-service`, `RequestsOpenAccess = true`) | The keyboard UI. Uses `ProtlyCore` and a vendored KeyboardKit 9.9.1. |
| `Protly` | container app | Settings only: API key, workspace ID, setup guide, a test text field. |

- **KeyboardKit 9.9.1** (MIT, last full-source tag) is vendored as source under `ios-app/Vendor/KeyboardKit/`
  with its license, pinned, never upgraded to 10.x (closed binary). Its asset catalogs are replaced with colors in
  code if xtool cannot compile them. It provides geometry, Liquid Glass styling, key callouts, gestures, space-bar
  cursor drag and backspace repeat. Korean input and autocomplete are ours (they are Pro-only there).
- **Shared state**: App Group container (`group.<bundle-prefix>.protly`) holds settings and the learned words. The
  container app writes, the keyboard reads (and writes learned words). The API key and workspace ID go in a shared
  Keychain access group if Sprint 2 shows it works on the free Apple ID; otherwise in the App Group container (a
  plain file only protly's two targets can read). Without Full Access the keyboard may not reach the App Group:
  typing then runs on built-in defaults with no learned words, and actions are off anyway.
- **Prompt**: a new file `ios/keyboard-prompt.txt`, owned by the keyboard. It is a different task from the
  screenshot prompt (text only, no screen, no chat header), so it is not a copy of `ios/system-prompt.txt`, which
  stays untouched together with the Shortcut, `body-template.json` and its tests. It keeps the same writer facts
  (Korean speaker, male) and the same JSON schema (`translation`, `back_translation`). Modes: in (non-Korean text to
  Korean), out (Korean to English), fix (English polish). No memos in v1: per-friend memos depend on the chat header,
  which a keyboard cannot see.
- **Models**: hardcoded, the split already used on the phone: in = `claude-sonnet-5-5`, thinking off; out and fix =
  Opus, adaptive thinking.
- **Request headers**: `x-api-key`, `anthropic-version`, and `anthropic-workspace-id`. The user's phone key is
  org-level and the API rejects it without the workspace header (2026-10-28, see `docs/ios-shortcut.md`).
- **Resource sync**: SwiftPM resources must live inside the target folder, so `scripts/sync-ios-app.mjs` copies
  `ios/keyboard-prompt.txt` into `ios-app/Sources/ProtlyKeyboard/Resources/`. A node test fails when the two differ,
  and the iOS build script runs the sync first.
- Python and JS tests of the existing repo keep running in `npm test`; `ios-app` adds `swift test` (Linux).

## What iOS draws and what protly draws

- In apps built with the iOS 26+ SDK, iOS draws the rounded glass container and the bottom globe/mic row for
  third-party keyboards too. protly's view sits inside, background clear. Apps on an older SDK show the legacy
  style; KeyboardKit has both.
- protly draws: the predictive bar (about 45 pt) and the key area (about 216 pt portrait). Total own height about
  261 pt, matched to the system keyboard by on-device comparison screenshots, not by estimate.

## Keyboard behavior

### Layout and typing

- One QWERTY key grid. Keycaps show ONE language at a time: English letters or Dubeolsik jamo. The grid switches
  automatically to match the detected language of the word being typed. At a word start it shows the language of
  the previous word (or of the field content).
- Every Apple behavior KeyboardKit already matches stays: key callouts, long-press alternates (English accents),
  shift one-shot and double-tap caps lock, auto-capitalization by `autocapitalizationType` (English only),
  backspace auto-repeat with word acceleration, double-space period, space long-press trackpad, return key label
  from `returnKeyType`, `keyboardAppearance`, input click sound and haptics (Full Access), 123 and #+= layouts.
- Korean shift gives ㅃㅉㄸㄲㅆ and ㅒㅖ and releases after one jamo. Backspace inside an unfinished syllable
  removes one jamo at a time.
- Emoji key: calls `advanceToNextInputMode()`. Setup tells the user to keep only protly plus Apple's Emoji keyboard
  enabled, so the key opens the system emoji keyboard and its ABC key returns to protly. Verified on device in
  Sprint 2; if it fails, the key is dropped and the space widens.

### Automatic language per word

- The keyboard keeps the raw key sequence of the current word. Each key event records its position and whether
  shift was MANUAL (user pressed shift or caps lock) or AUTOMATIC (auto-capitalization). The English reading honors
  both; the Korean reading honors manual shift only, so an auto-capitalized sentence start never turns ㅂ into ㅃ.
- `ProtlyCore` produces both readings, the Dubeolsik composition and the Latin string, and scores them (valid Hangul
  syllable structure, Korean word list, English word list, and from Sprint 6 the user's learned words).
- The winning reading is shown while typing, never as a correction after the fact. Composition is shown with
  `setMarkedText`/`unmarkText` (delete-and-reinsert loses characters in web views); if Sprint 2 shows a
  disturbing underline in Instagram or KakaoTalk, the fallback is decided then with evidence.
- Space commits the word. A quick horizontal flick on the space bar (distinct from the long-press trackpad) flips
  the last word to the other reading and records the correction for learning.
- Target accuracy is set from the Sprint 1 measurement, not guessed, and re-measured in Sprint 6 with learned words.

### Predictive bar

- Left: a small protly icon, fixed width. Right: three slots like Apple's (quoted typed word, best candidate in the
  middle, alternative).
- The protly icon runs the action that fits now: Translate/Polish on the field (or selection) when it has text; read
  the clipboard when the field is empty.
- While a word is being typed: completions. English: word-list completion plus autocorrect on space (only when the
  candidate is far more frequent than the typed word, never for learned or lexicon words, undone by backspace like
  Apple). Korean: whole-word completion matched on decomposed jamo, no autocorrect. Text replacements from
  `UILexicon` apply.
- While no word is being typed and the field has text: the middle slot shows ONE action, `Translate` when the field
  is Korean, `Polish` when it is English; the side slots stay empty. Empty field: all slots empty. Selected text
  (via the host app's own Select menu) makes the action apply to the selection only.
- Word data: memory-mapped binary lists, total under 15 MB (English top 50k from wordfreq; Korean whole-word list
  from a subtitle-derived source). Both lists are chosen in Sprint 1, because the detector needs them; Sprint 6
  reuses them for completion. Learned words live in the App Group and rank first.

### Panel (same height as the key area)

- Write: tap `Translate`/`Polish` (or the protly icon) -> read the whole field (walk the cursor with
  `adjustTextPosition`, or `selectedText` when there is a selection) -> API call with a spinner -> the key area is
  replaced by a panel showing the result and, for Translate, the Korean back translation -> `Insert` replaces the
  field (or selection), `Cancel` returns to keys. After Insert, `Undo` in the bar restores the original text.
- Read: when the keyboard appears or regains focus, the clipboard holds new text (change count differs from the
  last seen), and the user is not mid-word, it translates it to Korean and shows it in the panel. Tap anywhere returns
  to keys. Skipped: Korean text, URLs, text equal to the field content, the same clipboard twice.
- If Sprint 2 shows a paste prompt on every keyboard clipboard read, automatic read is dropped and read runs only from
  the protly icon on an empty field.
- The panel never adds height.

### Errors

Nothing touches the field on failure; the bar shows a short English message:

- Full Access off: "Turn on Full Access in Settings to use protly actions" (typing still works without it).
- No API key, network error, timeout (30 s), API error: message plus retry.
- Truncated field read (cursor walk does not reach both ends): "Select all, then tap again".
- Clipboard read denied: read mode stays silent.

## Container app

English UI, one screen: API key and workspace ID (never logged, never in the repo), setup steps (add keyboard, Full
Access, remove Apple Korean/English keyboards, keep Emoji), and a test text field. No model choice, no memos, no
feature switches in v1.

## Sprints

Each sprint ends with tests green; Sprints 2-6 also end with a user check on the phone.

1. **ProtlyCore on Linux.** Install the Swift toolchain on Fedora. Choose and pack the English and Korean word
   lists. Dubeolsik composer (libhangul as reference), raw key model with manual/automatic shift, language detector,
   a corpus of Korean chat sentences and English sentences converted to key sequences, word-level accuracy report.
   No phone.
2. **xtool spike (parallel with 1).** Install xtool, build the SDK, build a minimal KeyboardKit-based keyboard plus
   container app, install with the free Apple ID. On the phone, record: extension builds and loads, Full Access,
   App Group sharing, Keychain access group on the free account, one API call with the workspace header, clipboard read prompt, `setMarkedText` look in Instagram/KakaoTalk/Messages,
   how much text `documentContext` returns there, emoji key round trip, own view height vs system keyboard.
   Gate: if the keyboard cannot be built or loaded, stop and re-plan.
3. **Full key layout + auto language.** Both keycap sets, all behaviors above, composer and detector wired in,
   space flick.
4. **Translate/Polish + panel + container app settings.**
5. **Clipboard read.**
6. **Completion, autocorrect, learning.**

## Testing

- `swift test` on Linux for all `ProtlyCore` logic: composer tables, backspace decomposition, detector corpus
  accuracy, completion ranking, autocorrect rules, request body vs `ios/body-template.json` shape, response parsing.
- The keyboard UI can only be checked on the phone by the user; each sprint ships a short checklist.
- `npm test` stays green (existing extension and iOS template tests).

## Known unknowns (checked in Sprint 2 unless noted)

- xtool building a keyboard extension and App Group on a free account; KeyboardKit 9.9.1 compiling under xtool.
- Paste prompt when a keyboard reads the clipboard.
- `documentContext` length in Instagram and KakaoTalk.
- Marked-text underline in those apps.
- Emoji key round trip through Apple's Emoji keyboard; whether Apple's Korean and English keyboards can both be
  removed.
- Shared Keychain access group on a free Apple ID.
- `UITextChecker` Korean support (Sprint 6).
- Exact system keyboard heights on the 13 Pro (measured from screenshots).
