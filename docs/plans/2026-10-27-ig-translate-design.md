# ig-translate: Instagram DM translation extension (design)

Date: 2026-10-27
Status: approved in brainstorm, pending spec review

## Goal

A personal Chrome extension for `instagram.com/direct`. Incoming non-Korean messages are shown
in Korean (or English), and Korean typed into the composer is translated into the partner's
language before sending, with a preview step. Translation is context-aware (recent messages plus
a per-thread memo) and runs on the Claude API.

Use case: casual chats with friends. Slang, emoji, casual register and tone must survive.

Non-goals: mobile Instagram app, group-chat specific features, automatic sending without user
confirmation, any server component.

## Decisions

| Topic | Decision |
|---|---|
| Platform | Chrome desktop, Manifest V3, plain JS, no build step, loaded unpacked |
| API path | Extension calls Anthropic API directly from the background service worker |
| API key | `chrome.storage.local`, entered on the options page. Console spend limit set to the $100/month credit |
| Incoming model | Sonnet 5.5, extended thinking off (latency first) |
| Outgoing model | Sonnet 5.5, effort `medium` (adaptive thinking) |
| Outgoing "hard" mode | Opus 5.5, effort `high`, triggered per message by `Alt+Enter` |
| Context | Last ~30 visible messages of the thread plus a per-thread memo |
| Send flow | Preview, then a second Enter sends |

The exact request parameters for effort / thinking on the 5.5 models are verified against the
current API docs during planning, not assumed here.

## Language rules

- Incoming, Korean: never translated.
- Incoming, English: translated to Korean.
- Incoming, any other language: translated to Korean or English, per-thread toggle, default Korean.
- Outgoing: Korean input is translated to the thread's output language.
  - Output language per thread: `auto` (default) or a fixed language code.
  - `auto` resolves to `partner_lang`, the language of the partner's most recent messages.
  - `partner_lang` is updated from the `src_lang` field Claude returns for incoming messages.
  - If `partner_lang` is unknown (new thread, no partner messages yet), fall back to English and
    show the chosen language in the preview so the user can change it.
- Composer text with no Hangul is sent as-is, no translation.

## Components

| File | Role |
|---|---|
| `manifest.json` | MV3. `host_permissions`: `https://www.instagram.com/*`, `https://api.anthropic.com/*`. Content script matches `https://www.instagram.com/direct/*` |
| `selectors.js` | Every Instagram DOM selector in one place. Prefer `role`, `aria-label`, `contenteditable`, structural anchors over obfuscated class names |
| `content.js` | Injected into DM pages. Detects messages with `MutationObserver`, renders translations, intercepts composer Enter, hosts the thread panel |
| `background.js` | Service worker. Owns every API call; the key never reaches the content script |
| `prompts.js` | System prompts for incoming batch translation, outgoing translation plus back-translation, memo suggestion |
| `options.html` / `options.js` | API key, model choice per direction, global defaults |

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

## Storage (`chrome.storage.local`)

- `settings`: API key, model per direction, global defaults for every panel toggle
- `threads[threadId]`: memo, `partner_lang`, output language, toggles
- `cache[hash]`: translation results keyed by hash of (threadId, message text, target language)
- `sent[hash]`: Korean original of each message sent through the extension, keyed by hash of
  (threadId, sent translated text)

`threadId` comes from the URL path `/direct/t/<id>`.

Cache growth: entries carry a timestamp; entries older than 90 days are pruned on startup.

## Data flow

### Incoming

1. On thread open, collect visible bubbles: text plus sender (me / partner). Skip messages with
   no text (images, reels, stickers, voice).
2. Skip Hangul-only text. Everything else goes to Claude, which returns `src_lang` per message.
3. Cache hit: render immediately. Misses are sent as **one batch call** containing the last ~30
   messages as context, the memo, and the list of messages to translate. Response is a JSON array
   of `{id, src_lang, translation}`. Messages Claude reports as Korean or English-to-English
   no-ops are left untouched.
4. New messages arriving later (`MutationObserver`) go through the same path as a batch of one,
   debounced so a burst of messages becomes one call.
5. Render according to the thread's display mode. In replace mode the original is available on
   hover.
6. My own past bubbles: if `sent[hash]` has the Korean original, show it on hover. They are not
   translated.

### Outgoing (preview)

1. `keydown` Enter in the composer is intercepted (capture phase, before Instagram's handler).
   `Shift+Enter` keeps its newline behaviour.
2. No Hangul in the text: let the event through untouched.
3. Hangul present: call Claude with recent context, memo, and target language. Response is
   `{translation, back_translation}`.
4. Composer text is replaced with the translation; the back-translation (Korean) and the model
   used are shown under the composer.
5. Second Enter sends whatever is in the composer, including user edits. `Esc` restores the
   original Korean and leaves preview state.
6. On send, store the Korean original in `sent`.
7. `Alt+Enter` does the same as step 3 onward with the Opus model.

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
| Missing / invalid key | One banner linking to the options page |
| Selector miss (Instagram changed) | Disable the extension on that page, set toolbar badge `!`. Never act on a guessed element |
| Enter pressed while a translation is pending | Ignored, prevents double send |
| Thread change during preview | Preview state discarded |
| Malformed JSON response | One re-request, then show failure |

## Privacy

Friends' DM text is sent to the Anthropic API. Accepted by the user. No other destination, no
telemetry.

## Testing

- **Prompts and parsing:** fixed fixture set of conversations (en, ru, es, ja mixed; casual
  register, slang, Korean subject drop). A script runs them through the API and checks JSON shape
  and `src_lang`. Translation quality is reviewed by eye.
- **DOM:** saved HTML snapshots of real Instagram DM pages, selector unit tests against them.
  When Instagram changes, take a new snapshot and diff.
- **Live check:** Claude in Chrome drives the real `instagram.com/direct` page to check incoming
  rendering and the preview flow. **Only the user presses the final send.** A test message to a
  friend cannot be taken back.
