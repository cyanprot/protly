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
