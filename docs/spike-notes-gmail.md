# Gmail spike notes (2026-10-28)

Live, Claude in Chrome, the user's own Gmail (English UI). Read-only except two throwaway drafts with no recipient,
both discarded with the compose's "Discard draft" button. No email content, names or addresses are recorded here.

## Compose

| Name | Selector / rule | Evidence |
|---|---|---|
| compose body | `div[role="textbox"][aria-label="Message Body"][contenteditable="true"]` | 1 per open compose; also carries `g_editable="true"`, `aria-multiline="true"`. Same in a new compose (dialog) and an inline reply |
| new compose window | `body.closest('[role="dialog"]')` | New compose is a `div[role="dialog"]`; an inline reply is NOT inside a dialog |
| compose container | nearest ancestor of the body that contains the Send button | Inline reply: the body is 13 levels below it. Works for both kinds |
| Send button | `[role="button"][data-tooltip^="Send"]` | Label/tooltip `Send (Ctrl-Enter)` (with bidi marks around the shortcut). Lives in `table[role="group"] > tbody > tr > td` (first of 6 cells) |
| our button slot | a new `td` right after the Send button's `td` | Inserted a probe `td > button`, it rendered visible, then removed |
| subject | `input[name="subjectbox"]` | Not needed |
| recipients | `input[role="combobox"][aria-label="To recipients"]`, chips are `div[role="option"]` with no email attribute | Not used: target language comes from the thread instead |
| Discard | `[role="button"][aria-label^="Discard draft"]` (Ctrl-Shift-D) | Used to clean up |

Send shortcut is Ctrl+Enter (from the tooltip). Plain Enter is a newline. Gmail enforces Trusted Types:
`insertAdjacentHTML` throws `This document requires 'TrustedHTML' assignment`, so extension code must build nodes
with `createElement` / `textContent` only.

## Body structure

- Empty compose: body is a single `<br>`.
- Text typed (via `execCommand('insertText')` with `\n`): first line is a bare text node, every further line is
  `<div>line</div>`, an empty line is `<div><br></div>`.
- Inline reply: the quoted history is NOT in the body; it sits behind a "Show trimmed content" button outside it. If
  the user expands it, it enters the body as `div.gmail_quote` (Gmail standard markup, not seen expanded here).
- Signature: this account has none. Gmail's standard markup is `span.gmail_signature_prefix` ("-- ") followed by
  `div.gmail_signature[data-smartmail="gmail_signature"]`. **[UNVERIFIED live]**: covered by the boundary rule below and
  by the live check.

Boundary rule for "the user's own part": body child nodes before the first node that is or contains
`.gmail_quote, blockquote, .gmail_signature, .gmail_signature_prefix`, minus trailing blank lines.

## Writing into the body

- `execCommand('insertText')` with a selection ending next to a block clones that block's class onto the inserted
  lines (a test `div.gmail_quote` spread onto the new lines). Not safe near quote/signature blocks.
- **Direct DOM replace works**: remove the user's nodes, insert `<div>` per line (`<div><br></div>` for blank lines)
  before the first remaining node, dispatch an `input` event. The quote block stayed intact and `innerText` showed the
  new text. Whether Gmail's draft autosave and Send pick up the DOM change is **[UNVERIFIED]** until the live check
  (Gmail sends the body DOM, so it is expected to).

## Thread view

| Name | Selector / rule | Evidence |
|---|---|---|
| message item | `[role="listitem"]` | 3 in a 3-message thread; `aria-expanded` false/false/true |
| message body | `div.a3s` inside the item | Only expanded items have it (collapsed ones show a snippet only). `a3s` is a Gmail class name, stable for years but not semantic; the only body anchor found |
| message id | ancestor `[data-message-id]` | Not needed |
| sender | `h3 span[email]` inside the item | Attributes `email`, `name`, `data-hovercard-id` |
| viewer email | `a[aria-label^="Google Account:"]`, label shape `Google Account: <name> (<email>)` | Also in `document.title` |
| reply link | `span[role="link"]` with text Reply | Opens the inline reply compose |

The last message of a thread is always expanded, so the most recent incoming message is readable for context.
