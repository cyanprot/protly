# ig-translate: Instagram DM translation extension (design)

Date: 2026-10-27
Status: approved; API path revised 2026-10-27 after the API spike (native messaging host)

## Goal

A personal Chrome extension for `instagram.com/direct`. Incoming non-Korean messages are shown
in Korean (or English), and Korean typed into the composer is translated into the partner's
language before sending, with a preview step. Translation is context-aware (recent messages plus
a per-thread memo) and runs on the Claude API.

Use case: casual chats with friends. Slang, emoji, casual register and tone must survive.

Non-goals: mobile Instagram app, group-chat specific features, automatic sending without user
confirmation, any always-on server component. (The native messaging host is started by Chrome on demand and
exits with the browser; it is not a server.)

## Decisions

| Topic | Decision |
|---|---|
| Platform | Chrome desktop, Manifest V3, plain JS, no build step, loaded unpacked |
| API path | Background service worker -> Chrome native messaging (`chrome.runtime.connectNative('com.northprot.ig_translate')`) -> stdlib Python host `host/ig_translate_host.py` -> Anthropic API. Direct browser calls are impossible: the organization rejects CORS requests (`401 "CORS requests are not allowed for this Organization because of its settings."`, Task 2 spike) |
| API key | Stays on disk in `~/.config/anthropic/api-key`. The host reads it, plus `workspace_id` from `~/.config/anthropic/configs/default.json` (sent as `anthropic-workspace-id`, required for this user-scoped key), on every request. The key never enters the browser. Console spend limit set to the $100/month credit |
| Incoming model | Sonnet 5.5, extended thinking off (latency first) |
| Outgoing model | Sonnet 5.5, effort `medium` (adaptive thinking) |
| Outgoing "hard" mode | Opus 5.5, effort `high`, triggered per message by `Alt+Enter` |
| Memo suggestion model | Same as outgoing (Sonnet 5.5, effort `medium`) |
| Context | Last ~30 visible messages of the thread plus a per-thread memo |
| Send flow | Preview, then a second Enter sends |

Request parameters for effort / thinking on the 5.5 models were verified against the API docs
and the Task 2 spike; the plan's "Verified API facts" section is the reference.

## Language rules

- Incoming, Korean: never translated.
- Incoming, English: translated to Korean.
- Incoming, any other language: translated to Korean or English, per-thread toggle, default Korean.
- Outgoing: Korean input is translated to the thread's output language.
  - Output language per thread: `auto` (default) or a fixed language code.
  - `auto` resolves to `partner_lang`, the language of the partner's most recent messages.
  - `partner_lang` is updated from the `src_lang` field Claude returns for incoming messages.
  - If `partner_lang` is unknown (new thread, no partner messages yet), fall back to English.
  - The preview always shows the target language as a clickable chip. Clicking it opens a small
    language picker; picking a language sets the thread's output language and re-translates from
    the stored Korean original.
- Composer text with no Hangul is sent as-is, no translation.

## Components

| File | Role |
|---|---|
| `manifest.json` | MV3. Permissions `storage`, `nativeMessaging`. `host_permissions`: `https://www.instagram.com/*` only (the browser never talks to the API). Content script matches all of `instagram.com` and activates on `/direct/t/<id>` (SPA navigation) |
| `selectors.js` | Every Instagram DOM selector in one place. Prefer `role`, `aria-label`, `contenteditable`, structural anchors over obfuscated class names |
| `content.js` | Injected into DM pages. Detects messages with `MutationObserver`, renders translations, intercepts composer Enter, hosts the thread panel |
| `background.js` | Service worker. Owns all storage and every API call, sent over one long-lived native messaging port (an open port also keeps the service worker alive during long calls) |
| `host/ig_translate_host.py` | Native messaging host, Python 3 stdlib only. Length-prefixed JSON on stdin/stdout, one thread per request, 120 s timeout. Reads the key and workspace ID from disk per request; never logs the key |
| `host/install.sh` | Writes `~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json` with `allowed_origins` set to this extension's ID |
| `prompts.js` | System prompts for incoming batch translation, outgoing translation plus back-translation, memo suggestion. ES module, shared with the Node fixture script; the service worker is declared `"type": "module"` and the repo `package.json` sets `"type": "module"` |
| `options.html` / `options.js` | Model choice per direction, global defaults. No API key field |

Instagram is an SPA: thread changes happen without page loads, so `content.js` watches URL
changes and re-initialises per thread.

### Thread panel (small overlay inside the DM page)

Per-thread controls:
- translation on/off
- output language: `auto` / fixed code
- non-English incoming target: Korean / English
- display mode for past messages: below bubble / replace bubble text
- display mode for new messages: below bubble / replace bubble text
- memo editor plus a "suggest memo" button

Defaults: new messages below the bubble, past messages replaced.

**Past vs new:** a message is *past* if it was in the DOM when the thread was initialised, or is
inserted above an already known message (Instagram back-fills history when scrolling up). It is
*new* only if it is appended below the last known message after initialisation.

## Storage (`chrome.storage.local`)

One storage key per entry, so a write never rewrites a whole map:

- `settings`: model per direction, global defaults for every panel toggle
- `t:<threadId>`: memo, `partner_lang`, output language, toggles
- `c:<hash>`: incoming translation. Key = hash of (threadId, message text, non-English target
  toggle value). Value = `{src_lang, translation, ts}`. The toggle value is known before the call,
  so lookup works without knowing `src_lang` first
- `s:<hash>`: Korean original of a message sent through the extension. Key = hash of
  (threadId, whitespace-normalized composer text at the moment of sending, after any user
  edits). Value = `{korean, ts}`

`threadId` comes from the URL path `/direct/t/<id>`.

Growth: `c:` and `s:` entries older than 90 days are pruned on startup.

## Data flow

### Incoming

1. On thread open, collect visible bubbles: text plus sender (me / partner). Skip messages with
   no text (images, reels, stickers, voice).
2. Skip Hangul-only text. Everything else goes to Claude, which returns `src_lang` per message.
3. Cache hit: render immediately. Misses are sent as **one batch call** containing the last ~30
   messages as context, the memo, and the list of messages to translate. The caller cannot assign
   a target per message, so the prompt states the rule: "English to Korean; any other non-Korean
   language to <toggle value>; Korean unchanged". Response is a JSON array of
   `{id, src_lang, translation}`. Messages Claude reports as Korean are left untouched.
4. Messages added later (`MutationObserver`) go through the same path, debounced so a burst
   becomes one call. Back-filled history and new arrivals share this path; they differ only in
   display mode (see "Past vs new").
5. `partner_lang` is updated only from the initial scan and from new arrivals, never from
   back-filled history or retries, so `auto` keeps following the partner's most recent language.
6. Render according to the thread's display mode. In replace mode the original is available on
   hover.
7. My own past bubbles: if `s:<hash>` has the Korean original, show it on hover. They are not
   translated.

### Outgoing (preview)

1. `keydown` Enter in the composer is intercepted (capture phase, before Instagram's handler).
   `Shift+Enter` keeps its newline behaviour.
2. No Hangul in the text: let the event through untouched.
3. Hangul present: call Claude with recent context, memo, and target language. Response is
   `{translation, back_translation}`.
4. The Korean original is kept in preview state. Composer text is replaced with the translation;
   the back-translation (Korean), the model used, and the target-language chip are shown under
   the composer.
5. Second Enter sends whatever is in the composer, including user edits. `Esc` restores the
   original Korean and leaves preview state.
6. On send, store the Korean original under `s:<hash>` (hash of the composer text as sent).
7. `Alt+Enter` outside preview: same as step 3 onward with the Opus model.
   `Alt+Enter` inside preview: re-translate the stored Korean original with Opus, replacing the
   current preview (user edits to the translation are discarded).
8. Changing the target language via the chip re-translates the stored Korean original with the
   model of the current preview.
9. Enter in preview while the composer holds Hangul (the user wrote a new Korean draft) starts a
   new translation of that text. It never sends raw Korean.
10. The composer emptying while in preview (Instagram's Send button, or the user deleted the text)
   ends the preview. A send through the button is recorded under `s:<hash>` like an Enter send.
11. Korean IME: Enter pressed mid-composition is blocked whenever the box holds Hangul or a
   translation is pending, and is handled once the composition commits.
12. A failed or cancelled re-translate puts the Korean original back in the composer.

The method for replacing composer text must make Instagram's own state see the new value
(Instagram's composer is a React-controlled contenteditable). Verifying that technique against
the live page is the first spike in the plan.

### Memo suggestion

"Suggest memo" sends recent messages to Claude, which returns a short draft (relationship, tone,
nicknames, running jokes). The draft fills the memo editor; it is saved only when the user saves.

## Error handling

| Case | Behaviour |
|---|---|
| Incoming API failure / timeout | Small retry marker next to the bubble; original text untouched |
| Outgoing API failure | Korean stays in the composer, red "translation failed" line. Never auto-send the original |
| 429 / overloaded | Exponential backoff, 2 retries, then show failure |
| Key file missing / key rejected | One banner naming `~/.config/anthropic/api-key` |
| Native host missing / not installed / crashed | Retried like a network error, then one banner pointing at `host/install.sh <extension id>`. Outgoing keeps the Korean, sends nothing. The next request reconnects |
| Selector miss (Instagram changed) | Disable the extension on that page, set toolbar badge `!`. Never act on a guessed element. If the composer is not recognised, a Hangul Enter in any editable box is blocked with a banner rather than sent raw |
| Translation could not be written into the composer | Preview cancelled, error note, nothing sent |
| Enter pressed while a translation is pending | Ignored, prevents double send |
| Thread change during preview | Preview state discarded |
| Malformed JSON response | One re-request, then show failure |

## Privacy

Friends' DM text is sent to the Anthropic API. Accepted by the user. No other destination, no
telemetry. The API key never enters the browser: it stays in `~/.config/anthropic/api-key` and
is read only by the native host process, which never logs it or returns it.

## Testing

- **Native host:** Python `unittest` (framing round trip, header building from a temp HOME,
  missing key file, HTTP and network errors, key never in output), run with
  `python3 -I host/test_host.py`.
- **Prompts and parsing:** fixed fixture set of conversations (en, ru, es, ja mixed; casual
  register, slang, Korean subject drop). A Node script (key and workspace from env vars, read
  from the config files inside the command) runs them through the API and checks JSON shape and
  `src_lang`. The script imports the same
  `prompts.js` as the extension. Translation quality is reviewed by eye.
- **DOM:** saved HTML snapshots of real Instagram DM pages, selector unit tests against them.
  When Instagram changes, take a new snapshot and diff.
- **Live check:** Claude in Chrome drives the real `instagram.com/direct` page to check incoming
  rendering and the preview flow. **Only the user presses the final send.** A test message to a
  friend cannot be taken back.
