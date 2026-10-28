# Gmail compose translation (design)

Date: 2026-10-28
Status: scope set by the user 2026-10-28; extends ig-translate

## Goal

In Gmail on the web, the user writes an email or reply in Korean, presses a Translate button (or Alt+T), and the draft
is replaced by a translation into the recipient's language with a Korean back-translation shown under the compose.
The user reviews and sends it with Gmail's own Send. Undo puts the Korean back.

Non-goals (user decision): translating incoming email, summaries. Also out: subject line translation, per-thread
memo, rich formatting inside the user's own text, attachments, Gmail mobile.

## Decisions

| Topic | Decision |
|---|---|
| Trigger | Explicit only: a `Translate` button next to Send, and `Alt+T` inside the compose body. Enter is a newline in email, so it is never intercepted |
| Send | Never done by the extension. The user sends with Gmail's Send / Ctrl+Enter. Sending an untranslated Korean draft is allowed (some emails are meant to be Korean) |
| Target language | `auto` by default: the model writes in the language of the most recent thread message not written by the viewer, else English. The model reports the language it used (`lang`). A picker in the note overrides it and re-translates |
| Register | Follow the thread's formality. New email with no thread: neutral-polite. Writer is male (same rule as DMs) |
| Model | Sonnet 5.5, effort medium (`email` profile). An `Opus` button in the note re-translates with the existing `hard` profile |
| Context | Expanded messages of the open thread, quoted history and signatures stripped, last 5 messages, 1500 chars each. A new compose window (dialog) gets no context |
| What is translated | Only the user's own part: body nodes before the first quote / signature block. Quote and signature nodes are never touched |
| Formatting | Paragraphs and line breaks kept. Inline formatting in the user's part (bold, links) is flattened to plain text. A draft containing images is refused with a note |
| Storage | None. No cache, no per-thread state, no Korean-original record |
| API path | Same as DMs: content script -> background `email` handler -> native host -> Claude API |
| Manifest | Second content script for `https://mail.google.com/*` with its own loader; `src/content/gmail/*.js` and `src/lib/*.js` web-accessible there |

## Components

| File | Role |
|---|---|
| `src/lib/prompts.js` | `email` profile, `EMAIL_SYSTEM`, `buildEmailRequest`, `parseEmail` (returns `{lang, translation, back_translation}`) |
| `src/background.js` | `email` message handler |
| `src/content/gmail/selectors.js` | Every Gmail DOM assumption (spike-notes-gmail.md) |
| `src/content/gmail/body.js` | Pure DOM helpers: user's part, text <-> nodes, replace with an `input` event |
| `src/content/gmail/thread.js` | Reads thread context |
| `src/content/gmail/compose.js` | Button, Alt+T action, note UI, preview state per compose |
| `src/content/gmail/main.js`, `loader.js`, `style.css` | Entry, observer for new composes, keyboard shortcut |

Instagram files are not touched.

## Flow

1. Gmail opens a compose. A debounced observer finds new compose bodies and adds the `Translate` button after Send.
2. Button or Alt+T (if the IME is mid-composition, wait for `compositionend`, max 500 ms):
   - user's part has no Hangul: note "No Korean text to translate", nothing else
   - user's part contains an image: refuse with a note
   - otherwise the state becomes `translating` and the note shows "Translating..."
3. Response: replace the user's part with the translation (one `<div>` per line), keep the removed Korean nodes, check
   the body now reads as the translation. If not, put the Korean back and show an error.
4. Note (preview): back-translation, language picker, model label, `Opus` and `Undo` buttons.
   - Picker or Opus: re-translate the stored Korean, replace the body again. The Korean nodes stay saved.
   - Undo: put the saved Korean nodes back (discards edits to the translation), note disappears.
   - The button / Alt+T in preview: if the user's part now holds new Korean text, start over with it; else no-op.
5. The user sends with Gmail. The compose disappears; its state is garbage with it (WeakMap).

## Errors

| Case | Behaviour |
|---|---|
| API / host error | Body untouched (or Korean restored), red note with the reason (auth, host, spend limit, timeout use the DM banner texts) |
| Result for an outdated request (Undo or a newer request meanwhile) | Ignored |
| Send button not found | Button not mounted, badge `!`; Alt+T still works |
| Viewer email not found | Every thread message counts as from them; console warning |
| Write check fails | Korean restored, red note |

## Privacy

The user's draft and up to 5 thread messages (truncated) go to the Anthropic API through the native host, the same
path and acceptance as DMs. Nothing is stored.

## Testing

- Unit (jsdom): selectors, body helpers and thread reader against a synthetic fixture whose shape follows
  `docs/spike-notes-gmail.md` (no real mail content anywhere); prompt builder and parser.
- Live: the user writes to their own address, translates, checks Undo / picker / Opus, and presses Send themselves.
