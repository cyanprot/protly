# Gmail Compose Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use execute-flow to implement this plan task-by-task.

**Goal:** In Gmail on the web, a Translate button (and Alt+T) turns the Korean draft of an email or reply into the thread's language with a back-translation note, Undo, a language picker and an Opus retry; the user sends with Gmail.

**Architecture:** A second content script for `mail.google.com` (own loader, files under `src/content/gmail/`) reads the user's part of the compose body and the open thread, asks the existing background service worker (new `email` handler), which calls Claude through the existing native messaging host. Pure DOM helpers are unit-tested in jsdom against a synthetic fixture shaped by the spike. Instagram files are untouched.

**Tech Stack:** Chrome MV3, plain ES modules, no build step; `node:test` + jsdom 30.1.3; Claude API through `host/ig_translate_host.py`.

Design: `docs/plans/2026-10-28-gmail-compose-design.md`. Spike facts: `docs/spike-notes-gmail.md`.

---

## Facts this plan relies on

- Compose body: `div[role="textbox"][aria-label="Message Body"][contenteditable="true"]`. New compose sits in `[role="dialog"]`, an inline reply does not.
- Send: `[role="button"][data-tooltip^="Send"]` inside `table[role="group"] td`. A `td` inserted after it renders.
- Body markup: first line bare text, then `<div>line</div>`, blank line `<div><br></div>`; empty body is `<br>`.
- Quote `.gmail_quote` / `blockquote`, signature `.gmail_signature_prefix` + `.gmail_signature`: never touched.
- Gmail enforces Trusted Types: no `innerHTML` / `insertAdjacentHTML`; build nodes with `createElement` / `textContent`.
- `execCommand('insertText')` next to a block clones its class; the plan uses direct DOM replace plus an `input` event instead.
- Thread: `[role="listitem"]`, expanded ones contain `div.a3s` (body) and `h3 span[email]` (sender). Viewer: `a[aria-label^="Google Account:"]`, label `Google Account: <name> (<email>)`.
- `[UNVERIFIED]`, checked in Task 8: Gmail autosave/Send pick up the direct DOM replace; content-script `import()` works under Gmail's CSP; `Alt+T` is not taken by Gmail; signature markup on an account that has one.
- Test command for one file: `node --test tests/<file>.test.js`; all: `npm test` (glob `tests/*.test.js`).

---

# Sprint 1: Spike (done)

### Task 1: Gmail DOM spike

Done 2026-10-28, recorded in `docs/spike-notes-gmail.md` (committed with this plan). Nothing to do.

---

# Sprint 2: Prompt and background

### Task 2: `email` prompt profile, builder and parser

**Files:**
- Modify: `src/lib/prompts.js`
- Test: `tests/prompts.test.js` (append)

**Step 1: Append the failing tests to `tests/prompts.test.js`**

```js
import { buildEmailRequest, parseEmail } from '../src/lib/prompts.js';

test('email request: auto target, thread roles, male writer, schema has lang', () => {
  const b = buildEmailRequest({
    model: 'claude-sonnet-5-5',
    context: [{ from: 'them', text: 'Dear Mr Kim' }, { from: 'me', text: 'Hello' }],
    korean: '확인했습니다',
  });
  assert.match(b.messages[0].content, /TARGET: auto/);
  assert.match(b.messages[0].content, /--- THEM:\nDear Mr Kim/);
  assert.match(b.messages[0].content, /KOREAN DRAFT:\n확인했습니다/);
  assert.match(b.system, /writer is male/);
  assert.deepEqual(b.output_config.format.schema.required, ['lang', 'translation', 'back_translation']);
  assert.equal(b.output_config.effort, 'medium');
  assert.equal('temperature' in b, false);
});

test('email request: fixed language, no thread, Opus hard profile', () => {
  const b = buildEmailRequest({ model: 'claude-opus-5-5', profile: 'hard', context: [], korean: '네', lang: 'ru' });
  assert.match(b.messages[0].content, /TARGET: Russian/);
  assert.match(b.messages[0].content, /new email/);
  assert.equal(b.output_config.effort, 'high');
  assert.deepEqual(b.thinking, { type: 'adaptive' });
});

test('parseEmail normalizes lang and rejects an empty translation', () => {
  assert.deepEqual(
    parseEmail(resp('{"lang":"EN-us","translation":"Confirmed.","back_translation":"확인했습니다."}')),
    { lang: 'en', translation: 'Confirmed.', back_translation: '확인했습니다.' },
  );
  assert.throws(() => parseEmail(resp('{"lang":"en","translation":"  ","back_translation":"x"}')), (e) => e.kind === 'parse');
  assert.throws(() => parseEmail(resp('{}', 'max_tokens')), (e) => e.kind === 'truncated');
});
```

`resp` is the helper already defined in this file. ES `import` declarations may appear anywhere at module top level.

**Step 2: Run, expect FAIL**

Run: `node --test tests/prompts.test.js`
Expected: FAIL, `buildEmailRequest` is not exported.

**Step 3: Implement in `src/lib/prompts.js`**

Add one line inside `PROFILES`, after `memo`:

```js
  email: { thinkingOff: false, effort: 'medium', max_tokens: 16000, useFormat: true },
```

Append at the end of the file:

```js
const EMAIL_SYSTEM = `You help a Korean speaker write emails: replies inside a thread and new emails.
Translate the Korean draft into the TARGET language.
- TARGET "auto": write in the language of the most recent thread message written by THEM. If there is none, write English.
- Register: match the formality of the thread. A formal email gets a formal reply, a casual one stays casual. With no thread, use a neutral, polite email style.
- The writer is male. Where the target language marks the speaker's gender, use masculine forms.
- Keep the draft's paragraphs and line breaks. Keep names, numbers, dates, URLs and email addresses exactly.
- Korean often drops the subject. Use the thread to decide who does what to whom.
- Do not add greetings, sign-offs, signatures or content that are not in the draft.
- lang: the ISO 639-1 code of the language you wrote in.
- back_translation: translate your output back into natural Korean so the writer can check the meaning.`;

const EMAIL_SCHEMA = {
  type: 'object',
  properties: {
    lang: { type: 'string' },
    translation: { type: 'string' },
    back_translation: { type: 'string' },
  },
  required: ['lang', 'translation', 'back_translation'],
  additionalProperties: false,
};

const formatEmailThread = (context) =>
  context.map((m) => `--- ${m.from === 'me' ? 'ME' : 'THEM'}:\n${m.text}`).join('\n\n') || '(none: this is a new email)';

// profile: 'email' (Sonnet, medium) or 'hard' (Opus, high). lang: 'auto' or an ISO 639-1 code.
export function buildEmailRequest({ model, profile = 'email', context, korean, lang = 'auto' }) {
  const text = [
    `TARGET: ${lang === 'auto' ? 'auto' : langName(lang)}`,
    `EMAIL THREAD (oldest first):\n${formatEmailThread(context)}`,
    `KOREAN DRAFT:\n${korean}`,
  ].join('\n\n');
  return request(model, profile, EMAIL_SYSTEM, text, EMAIL_SCHEMA);
}

export function parseEmail(resp) {
  const j = extractJson(resp);
  if (typeof j.translation !== 'string' || !j.translation.trim() || typeof j.back_translation !== 'string') {
    throw new ApiError('parse', 'translation fields missing');
  }
  const lang = typeof j.lang === 'string' ? j.lang.toLowerCase().split(/[-_]/)[0] : 'und';
  return { lang, translation: j.translation, back_translation: j.back_translation };
}
```

**Step 4: Run, expect PASS**

Run: `npm test`
Expected: all PASS (the 3 new tests included).

**Step 5: Commit**

```bash
git add src/lib/prompts.js tests/prompts.test.js
git commit -m "feat: email prompt profile, builder and parser"
```

---

### Task 3: Background `email` handler, manifest, email eval

**Files:**
- Modify: `src/background.js`, `manifest.json`
- Test: `tests/smoke.test.js` (append)
- Create: `scripts/eval-email.mjs`

**Step 1: Append the failing test to `tests/smoke.test.js`**

```js
test('manifest injects the Gmail loader on mail.google.com', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  const g = m.content_scripts.find((c) => c.matches.includes('https://mail.google.com/*'));
  assert.deepEqual(g.js, ['src/content/gmail/loader.js']);
  assert.deepEqual(g.css, ['src/content/gmail/style.css']);
  const war = m.web_accessible_resources.find((w) => w.matches.includes('https://mail.google.com/*'));
  assert.ok(war.resources.includes('src/content/gmail/*.js'));
  assert.ok(war.resources.includes('src/lib/*.js'));
});
```

Run: `node --test tests/smoke.test.js`
Expected: FAIL (`g` is undefined).

**Step 2: Update `manifest.json`**

Read the file first. Append to the `content_scripts` array:

```json
    {
      "matches": ["https://mail.google.com/*"],
      "js": ["src/content/gmail/loader.js"],
      "css": ["src/content/gmail/style.css"],
      "run_at": "document_idle"
    }
```

Append to the `web_accessible_resources` array:

```json
    {
      "resources": ["src/content/gmail/*.js", "src/lib/*.js"],
      "matches": ["https://mail.google.com/*"]
    }
```

Change `description` to `"Translate Instagram DMs and Gmail drafts with Claude."`. No new permission is needed: content-script matches grant injection, and every API call already goes through the native host.

Run: `node --test tests/smoke.test.js`
Expected: PASS.

**Step 3: Add the handler to `src/background.js`**

Add `buildEmailRequest` and `parseEmail` to the existing import from `./lib/prompts.js`. Add after the `suggestMemo` function:

```js
// Gmail drafts. No storage: nothing is cached or remembered per thread.
async function email({ context, korean, profile, lang }) {
  const settings = await getSettings();
  const hard = profile === 'hard';
  const model = hard ? settings.models.hard : settings.models.outgoing;
  const body = buildEmailRequest({ model, profile: hard ? 'hard' : 'email', context, korean, lang: lang || 'auto' });
  const r = await api(body, parseEmail);
  return { ...r, model };
}
```

Add `email` to the `handlers` object next to `outgoing`.

Run: `node --check src/background.js && npm test`
Expected: no syntax error, all PASS.

**Step 4: Write `scripts/eval-email.mjs`**

```js
// Usage:
//   ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)" \
//   ANTHROPIC_WORKSPACE_ID="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/anthropic/configs/default.json")))["workspace_id"])')" \
//   node scripts/eval-email.mjs
import { callJson } from '../src/lib/api.js';
import { buildEmailRequest, parseEmail } from '../src/lib/prompts.js';

const key = process.env.ANTHROPIC_API_KEY;
const workspace = process.env.ANTHROPIC_WORKSPACE_ID;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }

const transport = async (body) => {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      ...(workspace ? { 'anthropic-workspace-id': workspace } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, retry_after: res.headers.get('retry-after'), body: await res.json().catch(() => ({})) };
};

// Synthetic threads only.
const cases = [
  {
    name: 'formal English reply', expect: 'en',
    context: [{ from: 'them', text: 'Dear Mr. Kim,\n\nCould you confirm whether the documents can be submitted by Friday?\n\nBest regards,\nProf. Allen' }],
    korean: '안녕하세요 교수님,\n\n금요일까지 제출 가능합니다. 혹시 추가로 필요한 서류가 있으면 알려주세요.\n\n감사합니다.',
  },
  {
    name: 'casual Russian reply', expect: 'ru',
    context: [{ from: 'them', text: 'Привет! Ну что, в субботу встречаемся? Напиши, во сколько удобно.' }],
    korean: '응 좋아! 3시쯤 어때? 늦으면 연락할게',
  },
  {
    name: 'new email, no thread', expect: 'en',
    context: [],
    korean: '안녕하세요, 다음 주 미팅 일정을 조율하고 싶습니다. 화요일이나 수요일 오후 중 편하신 시간을 알려주세요.',
  },
];

let failures = 0;
for (const c of cases) {
  const t0 = Date.now();
  const r = await callJson(buildEmailRequest({ model: 'claude-sonnet-5-5', context: c.context, korean: c.korean }), parseEmail, { transport });
  const ok = r.lang === c.expect;
  if (!ok) failures++;
  console.log(`\n=== ${c.name} [${ok ? 'ok' : 'FAIL'}] ${r.lang} ${Date.now() - t0}ms\n${r.translation}\n<- ${r.back_translation}`);
}
console.log(`\n${failures} lang failure(s)`);
process.exit(failures ? 1 : 0);
```

Run the usage command from the header (it reads the key and workspace inside the command and never prints them).
Expected: `0 lang failure(s)`; the English reply is formal, the Russian one casual and masculine, the new email polite. Show the output to the user for an eye check.

**Step 5: Commit**

```bash
git add src/background.js manifest.json tests/smoke.test.js scripts/eval-email.mjs
git commit -m "feat: background email handler, Gmail manifest entries, email eval"
```

---

# Sprint 3: Gmail content script

### Task 4: Fixture and selectors

**Files:**
- Create: `tests/fixtures/gmail.html`, `src/content/gmail/selectors.js`
- Test: `tests/gmail.test.js`

**Step 1: Write `tests/fixtures/gmail.html`**

Synthetic. Its shape follows `docs/spike-notes-gmail.md`; no real mail content.

```html
<a aria-label="Google Account: Viewer Name (viewer@example.com)" href="#"></a>
<div role="main">
  <div role="list">
    <div role="listitem" aria-expanded="false"><h3><span email="friend@example.com" name="Friend">Friend</span></h3><span>collapsed snippet</span></div>
    <div role="listitem" aria-expanded="true"><h3><span email="Viewer@Example.com" name="Viewer">Viewer</span></h3><div class="a3s aiL"><div dir="ltr">Sure, see you then.</div></div></div>
    <div role="listitem" aria-expanded="true"><h3><span email="friend@example.com" name="Friend">Friend</span></h3><div class="a3s aiL"><div dir="ltr">Could we move it to Friday?<br>Thanks</div><div class="gmail_quote">On Monday someone wrote: old text</div></div></div>
  </div>
  <div class="reply">
    <div role="textbox" aria-label="Message Body" contenteditable="true" g_editable="true" aria-multiline="true">한글 첫줄<div>둘째 줄</div><div><br></div><div>셋째 문단</div><div><br></div><span class="gmail_signature_prefix">-- </span><br><div class="gmail_signature" data-smartmail="gmail_signature">Sig</div></div>
    <table role="group"><tbody><tr><td><div role="button" data-tooltip="Send (Ctrl-Enter)">Send</div></td><td></td></tr></tbody></table>
  </div>
</div>
<div role="dialog">
  <div><div role="textbox" aria-label="Message Body" contenteditable="true" g_editable="true"><br></div></div>
  <table role="group"><tbody><tr><td><div role="button" data-tooltip="Send (Ctrl-Enter)">Send</div></td></tr></tbody></table>
</div>
```

**Step 2: Write the failing test `tests/gmail.test.js`**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { GSEL, composeOf, findViewerEmail } from '../src/content/gmail/selectors.js';

const html = readFileSync(new URL('./fixtures/gmail.html', import.meta.url), 'utf8');
const load = () => new JSDOM(`<body>${html}</body>`).window.document;

test('viewer email comes from the account link, lowercased', () => {
  assert.equal(findViewerEmail(load()), 'viewer@example.com');
  assert.equal(findViewerEmail(new JSDOM('<body></body>').window.document), null);
});

test('composeOf finds the inline reply and the dialog compose', () => {
  const doc = load();
  const [inline, dialog] = doc.querySelectorAll(GSEL.body);
  assert.ok(composeOf(inline).classList.contains('reply'));
  assert.equal(composeOf(dialog).getAttribute('role'), 'dialog');
  assert.ok(composeOf(inline).querySelector(GSEL.send));
});
```

Run: `node --test tests/gmail.test.js`
Expected: FAIL, module `selectors.js` not found.

**Step 3: Write `src/content/gmail/selectors.js`**

```js
// Every Gmail DOM assumption lives here (docs/spike-notes-gmail.md). When Gmail changes, re-check and edit this file.
export const GSEL = {
  body: 'div[role="textbox"][aria-label="Message Body"][contenteditable="true"]',
  send: '[role="button"][data-tooltip^="Send"]',
  threadItem: '[role="listitem"]',
  messageBody: 'div.a3s', // Gmail class name, the only body anchor; expanded messages only
  sender: 'h3 span[email]',
  account: 'a[aria-label^="Google Account:"]',
  // Blocks in a body that are not the user's own text and must never be rewritten.
  boundary: '.gmail_quote, blockquote, .gmail_signature, .gmail_signature_prefix',
};

// The compose container: nearest ancestor of the body that holds the Send button.
export function composeOf(body) {
  let c = body.parentElement;
  while (c && !c.querySelector(GSEL.send)) c = c.parentElement;
  return c;
}

// Label shape: "Google Account: <name> (<email>)". null if not found.
export function findViewerEmail(doc) {
  const label = doc.querySelector(GSEL.account)?.getAttribute('aria-label') || '';
  const m = label.match(/\(([^()\s]+@[^()\s]+)\)\s*$/);
  return m ? m[1].toLowerCase() : null;
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/gmail.test.js`
Expected: 2 tests PASS.

**Step 5: Commit**

```bash
git add tests/fixtures/gmail.html src/content/gmail/selectors.js tests/gmail.test.js
git commit -m "feat: Gmail selectors with synthetic fixture"
```

---

### Task 5: Body helpers

**Files:**
- Create: `src/content/gmail/body.js`
- Test: `tests/gmail.test.js` (append)

**Step 1: Append the failing tests**

```js
import { userNodes, nodesToText, textToNodes, replaceUserNodes, hasMedia } from '../src/content/gmail/body.js';

test('user part stops before the signature and its blank separator lines', () => {
  const body = load().querySelector(GSEL.body);
  assert.equal(nodesToText(userNodes(body)), '한글 첫줄\n둘째 줄\n\n셋째 문단');
});

test('a quote block is a boundary too', () => {
  const doc = new JSDOM('<body><div id="b"><div>안녕</div><br><div class="gmail_quote">old</div></div></body>').window.document;
  assert.equal(nodesToText(userNodes(doc.getElementById('b'))), '안녕');
});

test('textToNodes and nodesToText round-trip paragraphs', () => {
  const t = 'Hi Anna,\n\nFriday works.\nThanks';
  assert.equal(nodesToText(textToNodes(load(), t)), t);
});

test('replace and restore keep the signature nodes and fire input events', () => {
  const doc = load();
  const body = doc.querySelector(GSEL.body);
  const sig = body.querySelector('.gmail_signature');
  let inputs = 0;
  body.addEventListener('input', () => inputs++);
  const saved = replaceUserNodes(body, textToNodes(doc, 'First line\nSecond'));
  assert.equal(nodesToText(userNodes(body)), 'First line\nSecond');
  assert.equal(body.querySelector('.gmail_signature'), sig);
  replaceUserNodes(body, saved);
  assert.equal(nodesToText(userNodes(body)), '한글 첫줄\n둘째 줄\n\n셋째 문단');
  assert.equal(body.querySelector('.gmail_signature'), sig);
  assert.equal(inputs, 2);
});

test('empty compose: the text goes in before the placeholder br', () => {
  const doc = load();
  const body = doc.querySelectorAll(GSEL.body)[1];
  assert.deepEqual(userNodes(body), []);
  replaceUserNodes(body, textToNodes(doc, 'Hello'));
  assert.equal(nodesToText(userNodes(body)), 'Hello');
});

test('hasMedia flags images in the user part', () => {
  const doc = new JSDOM('<body><div id="b">글<div><img src="x"></div></div></body>').window.document;
  assert.equal(hasMedia(userNodes(doc.getElementById('b'))), true);
  assert.equal(hasMedia(userNodes(load().querySelector(GSEL.body))), false);
});
```

Run: `node --test tests/gmail.test.js`
Expected: FAIL, module `body.js` not found.

**Step 2: Write `src/content/gmail/body.js`**

```js
import { GSEL } from './selectors.js';

const BLOCK = /^(DIV|P|LI|H[1-6]|UL|OL|BLOCKQUOTE)$/;
const MEDIA = 'img, video, iframe';

const isBoundary = (n) => n.nodeType === 1 && (n.matches(GSEL.boundary) || !!n.querySelector(GSEL.boundary));
const isBlank = (n) =>
  n.nodeName === 'BR' ||
  (n.nodeType === 3 && !n.textContent.trim()) ||
  (n.nodeType === 1 && !n.textContent.trim() && !n.querySelector(MEDIA));

// The user's own part: body children before the first quote/signature block, minus trailing blank lines
// (those separate the draft from the signature and stay untouched).
export function userNodes(body) {
  const kids = [...body.childNodes];
  let end = kids.findIndex(isBoundary);
  if (end === -1) end = kids.length;
  while (end > 0 && isBlank(kids[end - 1])) end--;
  return kids.slice(0, end);
}

export const hasMedia = (nodes) => nodes.some((n) => n.nodeType === 1 && (n.matches(MEDIA) || !!n.querySelector(MEDIA)));

// Plain text with one \n per line, matching how Gmail lays out typed text (bare first line, <div> per line).
// Inline formatting is dropped.
export function nodesToText(nodes) {
  let out = '';
  const walk = (n) => {
    if (n.nodeType === 3) { out += n.textContent; return; }
    if (n.nodeType !== 1) return;
    if (n.nodeName === 'BR') { out += '\n'; return; }
    const block = BLOCK.test(n.nodeName);
    if (block && out && !out.endsWith('\n')) out += '\n';
    n.childNodes.forEach(walk);
    if (block && !out.endsWith('\n')) out += '\n';
  };
  nodes.forEach(walk);
  return out.replace(/\n$/, '');
}

// Gmail's own markup: <div>line</div>, blank line <div><br></div>. Built without innerHTML (Trusted Types).
export function textToNodes(doc, text) {
  return text.replace(/\r\n?/g, '\n').split('\n').map((line) => {
    const d = doc.createElement('div');
    if (line) d.textContent = line;
    else d.appendChild(doc.createElement('br'));
    return d;
  });
}

// Swap the user's part for newNodes; returns the removed nodes (for Undo). Quote and signature stay put.
// execCommand is not used: next to a block it clones the block's class onto the new lines (spike).
export function replaceUserNodes(body, newNodes) {
  const old = userNodes(body);
  const next = old.length ? old[old.length - 1].nextSibling : body.firstChild;
  old.forEach((n) => n.remove());
  const frag = body.ownerDocument.createDocumentFragment();
  newNodes.forEach((n) => frag.appendChild(n));
  body.insertBefore(frag, next);
  body.dispatchEvent(new body.ownerDocument.defaultView.Event('input', { bubbles: true }));
  return old;
}
```

**Step 3: Run, expect PASS**

Run: `node --test tests/gmail.test.js`
Expected: 8 tests PASS.

**Step 4: Commit**

```bash
git add src/content/gmail/body.js tests/gmail.test.js
git commit -m "feat: Gmail body helpers: user part, text and node conversion, replace"
```

---

### Task 6: Thread reader

**Files:**
- Create: `src/content/gmail/thread.js`
- Test: `tests/gmail.test.js` (append)

**Step 1: Append the failing tests**

```js
import { readThread } from '../src/content/gmail/thread.js';

test('readThread: expanded messages only, me/them by email, quotes stripped', () => {
  const doc = load();
  assert.deepEqual(readThread(doc.querySelector('[role="main"]'), 'viewer@example.com'), [
    { from: 'me', text: 'Sure, see you then.' },
    { from: 'them', text: 'Could we move it to Friday?\nThanks' },
  ]);
});

test('readThread keeps the last N and truncates long bodies', () => {
  const doc = load();
  assert.deepEqual(
    readThread(doc.querySelector('[role="main"]'), 'viewer@example.com', { maxMessages: 1, maxChars: 5 }),
    [{ from: 'them', text: 'Could [...]' }],
  );
});

test('readThread without a viewer email marks everything as them', () => {
  const t = readThread(load().querySelector('[role="main"]'), null);
  assert.deepEqual(t.map((m) => m.from), ['them', 'them']);
});
```

Run: `node --test tests/gmail.test.js`
Expected: FAIL, module `thread.js` not found.

**Step 2: Write `src/content/gmail/thread.js`**

```js
import { GSEL } from './selectors.js';
import { nodesToText } from './body.js';

// Context for a reply: expanded messages of the open thread, oldest first. Collapsed messages have no body
// in the DOM and are skipped; the last message of a thread is always expanded.
export function readThread(root, viewerEmail, { maxMessages = 5, maxChars = 1500 } = {}) {
  const out = [];
  for (const item of root.querySelectorAll(GSEL.threadItem)) {
    const body = item.querySelector(GSEL.messageBody);
    if (!body) continue;
    const clone = body.cloneNode(true);
    clone.querySelectorAll(GSEL.boundary).forEach((n) => n.remove()); // quoted history, signatures
    let text = nodesToText([...clone.childNodes]).replace(/\n{3,}/g, '\n\n').trim();
    if (!text) continue;
    if (text.length > maxChars) text = `${text.slice(0, maxChars)} [...]`;
    const email = item.querySelector(GSEL.sender)?.getAttribute('email')?.toLowerCase();
    out.push({ from: viewerEmail && email === viewerEmail ? 'me' : 'them', text });
  }
  return out.slice(-maxMessages);
}
```

**Step 3: Run, expect PASS**

Run: `node --test tests/gmail.test.js`
Expected: 11 tests PASS.

**Step 4: Commit**

```bash
git add src/content/gmail/thread.js tests/gmail.test.js
git commit -m "feat: Gmail thread reader for reply context"
```

---

### Task 7: Compose UI, entry, loader, style

**Files:**
- Create: `src/content/gmail/compose.js`, `src/content/gmail/main.js`, `src/content/gmail/loader.js`, `src/content/gmail/style.css`

This is page glue; Task 8 tests it live.

**Step 1: Write `src/content/gmail/compose.js`**

```js
import { GSEL, composeOf, findViewerEmail } from './selectors.js';
import { userNodes, nodesToText, textToNodes, replaceUserNodes, hasMedia } from './body.js';
import { readThread } from './thread.js';
import { hasHangul, LANG_NAMES } from '../../lib/lang.js';

const ERRORS = {
  auth: 'API key missing or rejected. Check ~/.config/anthropic/api-key.',
  host: 'Native host not reachable. Run host/install.sh <extension id>, then reload the extension.',
  spend_limit: 'Monthly API spend limit reached.',
  timeout: 'The model took too long. Try again.',
};
const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');
const states = new WeakMap(); // compose body -> state; dropped with the compose
const mounted = new WeakSet();

async function ask(msg) {
  const r = await chrome.runtime.sendMessage(msg);
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
}

function stateOf(body) {
  let s = states.get(body);
  if (!s) {
    s = { mode: 'idle', reqId: 0, saved: null, korean: null, shown: null, lang: 'auto', profile: 'email', note: null, anchor: null };
    states.set(body, s);
  }
  return s;
}

export function mountCompose(body) {
  if (mounted.has(body)) return;
  mounted.add(body);
  const s = stateOf(body);
  const sendCell = composeOf(body)?.querySelector(GSEL.send)?.closest('td');
  if (!sendCell) {
    console.warn('[igt] Gmail Send button not found; Translate button not mounted (Alt+T still works)');
    ask({ type: 'badge', text: '!' }).catch(() => {});
    return;
  }
  s.anchor = sendCell.closest('table');
  const td = document.createElement('td');
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'igt-g-btn';
  btn.textContent = 'Translate';
  btn.title = 'Translate the Korean draft (Alt+T)';
  btn.addEventListener('click', () => translate(body));
  td.appendChild(btn);
  sendCell.after(td);
}

const span = (t) => { const e = document.createElement('span'); e.textContent = t; return e; };
function button(label, onClick) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = label;
  b.addEventListener('click', onClick);
  return b;
}

function showNote(body, s, children, isError = false) {
  if (!s.note?.isConnected) {
    s.note = document.createElement('div');
    s.note.className = 'igt-g-note';
    if (s.anchor?.isConnected) s.anchor.before(s.note); else body.after(s.note);
  }
  s.note.classList.toggle('igt-g-err', isError);
  s.note.replaceChildren(...children);
}

function hideNote(s) {
  s.note?.remove();
  s.note = null;
}

function langPicker(body, current) {
  const sel = document.createElement('select');
  const codes = Object.keys(LANG_NAMES).filter((c) => c !== 'ko');
  if (!codes.includes(current)) codes.unshift(current);
  for (const c of codes) {
    const o = document.createElement('option');
    o.value = c;
    o.textContent = LANG_NAMES[c] || c;
    o.selected = c === current;
    sel.appendChild(o);
  }
  sel.addEventListener('change', () => retranslate(body, { lang: sel.value }));
  return sel;
}

function showPreview(body, s, r) {
  showNote(body, s, [
    span(`${r.back_translation}  · ${modelLabel(r.model)}`),
    langPicker(body, r.lang),
    button('Opus', () => retranslate(body, { profile: 'hard' })),
    button('Undo', () => undo(body)),
  ]);
}

// Translate button and Alt+T.
export function translate(body) {
  const s = stateOf(body);
  if (s.mode === 'translating') return;
  const nodes = userNodes(body);
  const text = nodesToText(nodes).trim();
  if (s.mode === 'preview') {
    if (!hasHangul(text) || norm(text) === norm(s.shown)) return; // nothing new to translate
    Object.assign(s, { mode: 'idle', saved: null }); // a new Korean draft replaced the preview
  }
  if (!hasHangul(text)) return showNote(body, s, [span('No Korean text to translate.')], true);
  if (hasMedia(nodes)) return showNote(body, s, [span('The draft contains images. Translate the text before adding images.')], true);
  return request(body, { korean: text, profile: 'email', lang: 'auto' });
}

// Picker and Opus in preview: same Korean, other language or model.
function retranslate(body, { lang, profile }) {
  const s = stateOf(body);
  if (s.mode !== 'preview') return;
  return request(body, { korean: s.korean, profile: profile ?? s.profile, lang: lang ?? s.lang });
}

export function undo(body) {
  const s = stateOf(body);
  if (s.saved) replaceUserNodes(body, s.saved);
  Object.assign(s, { mode: 'idle', saved: null, korean: null, shown: null, lang: 'auto', profile: 'email' });
  s.reqId++; // drop any result still in flight
  hideNote(s);
}

async function request(body, { korean, profile, lang }) {
  const s = stateOf(body);
  const prevMode = s.mode;
  const reqId = ++s.reqId;
  s.mode = 'translating';
  showNote(body, s, [span(profile === 'hard' ? 'Translating with Opus...' : 'Translating...')]);
  try {
    const root = document.querySelector('[role="main"]');
    const context = body.closest('[role="dialog"]') || !root ? [] : readThread(root, findViewerEmail(document));
    const r = await ask({ type: 'email', context, korean, profile, lang });
    if (reqId !== s.reqId || !body.isConnected) return;
    const removed = replaceUserNodes(body, textToNodes(document, r.translation));
    if (prevMode !== 'preview') s.saved = removed; // first translation: keep the Korean nodes for Undo
    if (norm(nodesToText(userNodes(body))) !== norm(r.translation)) {
      replaceUserNodes(body, s.saved);
      Object.assign(s, { mode: 'idle', saved: null });
      return showNote(body, s, [span('Could not write the translation into the email. The Korean draft is back.')], true);
    }
    Object.assign(s, { mode: 'preview', korean, shown: r.translation, lang: r.lang, profile });
    showPreview(body, s, r);
  } catch (e) {
    if (reqId !== s.reqId) return;
    s.mode = prevMode;
    const parts = [span(`Translation failed: ${ERRORS[e.kind] || e.message}`)];
    if (s.saved) parts.push(button('Undo', () => undo(body)));
    showNote(body, s, parts, true);
  }
}
```

**Step 2: Write `src/content/gmail/main.js`**

```js
import { GSEL } from './selectors.js';
import { mountCompose, translate } from './compose.js';

const SCAN_MS = 300;
const COMPOSE_WAIT_MS = 500;

export async function start() {
  let timer = null;
  const scan = () => { timer = null; document.querySelectorAll(GSEL.body).forEach(mountCompose); };
  // Throttle, not debounce: Gmail mutates the page often enough that a debounce could never fire.
  new MutationObserver(() => { timer ??= setTimeout(scan, SCAN_MS); })
    .observe(document.body, { childList: true, subtree: true });
  scan();

  // Alt+T inside a compose body. e.code, because the Korean layout reports e.key as 'ㅅ'.
  document.addEventListener('keydown', (e) => {
    if (!e.altKey || e.ctrlKey || e.metaKey || e.shiftKey || e.code !== 'KeyT') return;
    const body = e.target?.closest?.(GSEL.body);
    if (!body) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (!e.isComposing && e.keyCode !== 229) { translate(body); return; }
    // IME mid-syllable: wait for the last syllable to commit.
    const go = () => { clearTimeout(t); translate(body); };
    const t = setTimeout(() => { body.removeEventListener('compositionend', go); translate(body); }, COMPOSE_WAIT_MS);
    body.addEventListener('compositionend', go, { once: true });
  }, true);
}
```

**Step 3: Write `src/content/gmail/loader.js`**

```js
// Classic content script for Gmail. Content scripts cannot be ES modules, so load the real entry dynamically.
(async () => {
  try {
    const { start } = await import(chrome.runtime.getURL('src/content/gmail/main.js'));
    await start();
  } catch (e) {
    console.error('[igt] Gmail part failed to load', e);
  }
})();
```

**Step 4: Write `src/content/gmail/style.css`**

```css
.igt-g-btn { margin-left: 8px; padding: 6px 12px; border-radius: 16px; border: 1px solid #888; background: transparent; color: inherit; cursor: pointer; font: 500 13px system-ui, sans-serif; }
.igt-g-note { margin: 6px 16px; padding: 6px 10px; border-radius: 6px; background: rgba(127, 127, 127, .12); font: 13px system-ui, sans-serif; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; white-space: pre-wrap; }
.igt-g-note.igt-g-err { color: #d93025; }
.igt-g-note button, .igt-g-note select { font: inherit; padding: 2px 8px; cursor: pointer; }
```

**Step 5: Syntax check and tests**

Run: `for f in src/content/gmail/*.js; do node --check "$f" || echo "FAIL $f"; done; npm test`
Expected: no `FAIL`, all tests PASS.

**Step 6: Commit**

```bash
git add src/content/gmail/compose.js src/content/gmail/main.js src/content/gmail/loader.js src/content/gmail/style.css
git commit -m "feat: Gmail compose button, Alt+T, preview note with picker, Opus and Undo"
```

---

### Task 8: Live check (manual, the user presses Send)

**Safety:** Claude never types into a Gmail compose and never clicks Send. Claude only observes (screenshots, `read_page`, reading the compose DOM shape without its text). The user does every keypress and click, and sends only to their own address.

**Step 1:** The user reloads the extension at `chrome://extensions` and reloads Gmail. Check: the DevTools console of the Gmail tab has no `[igt] Gmail part failed to load` (this answers the CSP / dynamic import question). If it fails, stop and report BLOCKED: the fallback is listing the Gmail modules as classic scripts, which changes Tasks 4-7.

**Step 2:** New compose to the user's own address, Korean body of two paragraphs. Check:
- [ ] a `Translate` button sits right of Send
- [ ] clicking it shows "Translating...", then the body turns English with the paragraph break kept
- [ ] the note shows the Korean back-translation, `Sonnet`, the picker on English, `Opus`, `Undo`

**Step 3:** The user clicks `Undo`. Check: the Korean comes back exactly, the note disappears.

**Step 4:** `Alt+T` with the last Korean syllable still composing. Check: translation starts after the syllable commits; Gmail does nothing else on Alt+T.

**Step 5:** The user picks Russian in the picker, then clicks `Opus`. Check: each re-translates the original Korean; the label changes to `Opus`.

**Step 6:** The user sends the translated draft (Send or Ctrl+Enter). Check in Sent: the received text is the translation, not the Korean (this answers the autosave/Send question).

**Step 7:** Reply case: the user opens a thread whose last message is in English (or Russian), clicks Reply, types Korean, presses `Translate`. Check: the language follows that message and the register matches it. If the account has a signature, check it is unchanged below the translation. Then the user expands the trimmed content and translates again: the quote block stays unchanged. The user may send it to themselves or discard.

**Step 8:** Host failure: Claude runs `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{,.off} && pkill -f '[i]g_translate_host.py'`. The user presses `Translate`. Check: the Korean stays, a red note names the host. Claude restores with `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{.off,}`.

**Step 9:** Record pass/fail per step in `docs/spike-notes-gmail.md` under `## Live check`, fix failures, commit.

```bash
git add docs/spike-notes-gmail.md
git commit -m "test: live Gmail compose check recorded"
```
