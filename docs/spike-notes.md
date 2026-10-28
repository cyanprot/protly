# Spike notes

## API spike (2026-10-27)

Key: `~/.config/anthropic/api-key` (`sk-ant-usr-...`, user-scoped). Requests with this key must send
`anthropic-workspace-id` (value in `~/.config/anthropic/configs/default.json` `workspace_id`), or the API
returns 400 "This API key is not scoped to a workspace".

| Variant | Status | Latency | Blocks |
|---|---|---|---|
| Sonnet `between_tools` + effort low + format | 200 | 3.9 s | text |
| Sonnet `adaptive` + effort medium + format | 200 | 2.8 s | text (no thinking used) |
| Opus `adaptive` + effort high + format | 200 | 3.7 s | thinking, text |
| Opus `between_tools` | 400 | | "thinking.type.between_tools is not supported for this model" |
| Sonnet `adaptive` medium, no format | 200 | 1.7 s | text, JSON wrapped in a ```json fence |

Findings:
- `output_config.format` works together with adaptive thinking. Keep `useFormat: true` everywhere.
- Opus rejects `between_tools`; `thinkingFor()` already gives Opus `adaptive`.
- Without `format`, Sonnet wraps JSON in a code fence. The parser's `{...}` extraction handles it.
- Latency is 1.7 to 3.9 s for a one-line message, single sample.

### Browser origin: BLOCKED

| Request | Status | Message |
|---|---|---|
| `Origin: chrome-extension://...`, no browser header | 401 | "CORS requests must set 'anthropic-dangerous-direct-browser-access' header" |
| same, WITH the header | 401 | "CORS requests are not allowed for this Organization because of its settings." |

The organization disallows browser-origin (CORS) requests. An extension service worker sends an
`Origin: chrome-extension://<id>` header on POST, so the design's direct-call path cannot work with this
organization. Requests with no `Origin` (Node) succeed. Plan Task 2 decision gate: BLOCKED, design
revisit needed for the API path only.

## Composer write (2026-10-27, live, no send)

Composer: `div[role="textbox"][contenteditable="true"][data-lexical-editor="true"]` (Lexical editor, 1 match).

- `el.focus(); document.execCommand('selectAll'); document.execCommand('insertText', false, text)` on an
  empty composer: text appears and Instagram shows its Send button. State follows.
- Replacing existing text: `getSelection().selectAllChildren(el)`, wait ~60 ms (Lexical syncs selection on
  `selectionchange`), then `execCommand('insertText', false, text)`. Works.
- Clearing to empty with `execCommand('delete')` does NOT work: returns true, Lexical keeps the text. Not needed,
  since the extension only ever replaces text with non-empty text. Real Ctrl+A, Backspace clears it.
- Empty composer `innerText` is `"\n"`; `getComposerText` strips the trailing newline.

`setComposerText` must therefore be: focus, `selectAllChildren`, wait 60 ms, `insertText`. It becomes async.

## Selectors (2026-10-27, live thread, 1:1 between the user's two accounts)

No hashed class names are used. Every selector is a role / aria / dir attribute.

| Name | Selector / rule | Evidence |
|---|---|---|
| `threadRoot` | `[role="main"]` | The message scroller has no attributes besides `class`; `main` holds it (and the inbox list, which has no `article` elements) |
| `messageRow` | `[role="article"][aria-roledescription="message"]` | 9 matches = 9 loaded messages; nothing else in the page uses that roledescription |
| `messageText` | `div[dir="auto"]` inside the article | Text bubbles are `span[dir=auto] > div[dir=auto]` (leaf). Shared posts/clips have only `span[dir=auto]` captions, so they are skipped. The day separator is a `span[dir=auto]` outside any article |
| sender | `article.closest('[role="group"]')` then `[aria-label^="Reply to message from "]`; the rest of the label is the username | Partner rows say `from northprot`, own rows `from cyanprot`. The actions group is a sibling of the article inside the row group, not inside the article |
| viewer username | first `a[href]` outside `[role="main"]` that contains `img[alt$="'s profile picture"]`; name = alt without `'s profile picture` | Exactly one such link: the sidebar profile link, alt `cyanprot's profile picture` |
| `composer` | `div[role="textbox"][contenteditable="true"]` | 1 match, also carries `data-lexical-editor="true"` |

`senderOf(article, viewer)` = `'me'` if the label name equals `viewer`, else `'partner'`. Group chats then treat
everyone else as partner, which is the safe direction.

Row layout (for reference only, not used): partner bubbles sit at left offset 51 px in the scroller, own bubbles
at right offset 31 px.

Mutations: hovering a message toggles `data-igd-message-actions-hidden` (attribute only). The observer uses
`childList`, so hover does not trigger it.

### Snapshot `tests/fixtures/thread.html`

Made with `scripts/sanitize-snapshot.js`. Every text node is `msg N`; usernames are `partner_user` / `viewer_user`;
only role, aria-label, aria-roledescription, dir and data-igd-message-actions-hidden attributes are kept. Grep for
the real names and message words: 0 hits.

Expected values (Task 15):
- `[role="article"][aria-roledescription="message"]` count: 9
- text rows (with `div[dir="auto"]`), in order: `msg 13`, `msg 17`, `msg 21`, `msg 25`, `msg 29`, `msg 33`, `msg 37`
- senders of those text rows with viewer `viewer_user`: partner x5, then me x2
  (`['partner','partner','partner','partner','partner','me','me']`)

## IME Enter

The log could not be read: Claude in Chrome cannot script or screenshot `file://` pages. The Task 20 handler covers both
possible orders (one composing keydown only, or composing keydown followed by a normal one), and Task 21
tests the real behaviour on Instagram. Not re-run, to save the user a second manual pass.

## Task 14 smoke test (2026-10-27)

Extension ID `dcfndjmllblfabckkelnflfmnkdochai` (derived from the folder path; computed before loading and confirmed on the card).
Host installed with `host/install.sh`.

Run from a temporary content-script loader on the test thread (content-script `console.log` is not visible to Claude in
Chrome, so the loader wrote its result into `document.documentElement.dataset.igtSmoke`):

| Check | Result |
|---|---|
| Content-script dynamic `import(chrome.runtime.getURL(...))` | OK, `hasHangul('안녕') === true` |
| content script -> background -> native host -> API, Sonnet outgoing | OK, 1.2 s |
| Same path, Opus `hard`, ru | OK, 5.8 s |
| Host alone (shell, framed stdin), Opus `hard` with the long 7-sentence text | OK, 23.5 s |

The >30 s case was not reached; the open port keeps the worker alive per Chrome 105+ docs, and the 150 s transport
timeout bounds it. Host-missing path (Step 6) skipped live: covered by `tests/native.test.js` (disconnect rejects with
Chrome's message, next call reconnects).

Russian output was feminine (`проспала`) until the outgoing prompt stated the writer is male (commit c0f852a).
