# ig-translate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use execute-flow to implement this plan task-by-task.

**Goal:** A personal Chrome MV3 extension that translates Instagram web DMs into Korean (or English) and turns Korean drafts into the partner's language through a preview-then-send flow, using the Claude API with conversation context and a per-thread memo.

**Architecture:** Plain ES modules, no build step, loaded unpacked. Pure logic lives in `src/lib/` and is unit-tested with `node --test`. The background service worker owns the API key, every API call and all storage. The content script is a thin DOM layer: it reads bubbles, renders translations, intercepts composer keys and hosts the thread panel, and asks the background for everything else via `chrome.runtime.sendMessage`.

**Tech Stack:** Chrome Manifest V3, vanilla JS (ESM), Anthropic Messages API over `fetch`, Node 22 `node:test`, `jsdom` (dev only, DOM snapshot tests).

**Design doc:** `docs/plans/2026-10-27-ig-translate-design.md` (read it first).

---

## Verified API facts (platform.claude.com, fetched 2026-10-27)

Use these exactly. Items marked `[UNVERIFIED]` are settled by the Task 2 spike before any code depends on them.

- Model IDs: `claude-sonnet-5-5`, `claude-opus-5-5`.
- Effort: top-level `output_config: { effort: "low" | "medium" | "high" | "xhigh" | "max" }`. GA, no beta header.
- Thinking on these models:
  - Omitting `thinking` means **adaptive thinking ON**, not off.
  - `{type: "disabled"}` returns 400 on both models.
  - Sonnet 5.5 "off": `thinking: { type: "between_tools" }`, only with effort `high` or lower, no other fields.
  - Opus 5.5 cannot turn thinking off. Use `thinking: { type: "adaptive" }`.
  - Thinking tokens count toward `max_tokens`. Response `content` has `thinking` blocks before `text` blocks; read only `type === "text"`.
- **Never send `temperature`, `top_p` or `top_k`.** They return 400 under the current API version.
- Structured output: `output_config: { format: { type: "json_schema", schema } }`. No beta header. The JSON is a string inside a `text` block. `stop_reason` `"refusal"` or `"max_tokens"` means the output may not match.
  - `[UNVERIFIED]` whether `format` works together with adaptive thinking.
- Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
  - `[UNVERIFIED]` whether `anthropic-dangerous-direct-browser-access: true` is required or accepted for extension-origin requests. Send it unless the spike shows a rejection.
- Errors:
  - 429 `rate_limit_error` carries a `retry-after` header in seconds. The exception is a 429 with `error.details.error_code === "enforced_spend_limit_reached"`: no `retry-after`, do not retry.
  - 529 `overloaded_error`: retry with backoff.
  - Other statuses: 401 auth, 402 billing, 403 permission, 500 api, 504 timeout.
  - Error body: `{type:"error", error:{type, message}, request_id}`.

## Verified extension and tooling facts (context7, 2026-10-27)

- Extension service workers support static `import` and `importScripts()`, but **not** dynamic `import()` (developer.chrome.com, service worker basics). `background.js` uses static imports only.
- `runtime.onMessage` listener may `return true` and call `sendResponse` later (runtime API reference).
- `web_accessible_resources` entries take `resources`, `matches` and optional `use_dynamic_url` (manifest reference).
- `[UNVERIFIED]` dynamic `import(chrome.runtime.getURL(...))` from a content script. Widely used, but not in the fetched docs. Task 12 Step 4 confirms it before Sprint 4.
- jsdom: `new JSDOM(html).window.document`. jsdom does **not** implement `innerText` (its WebIDL comments it out), so readers fall back to `textContent`.

## Request profiles

| Profile | Model (default) | thinking | effort | max_tokens |
|---|---|---|---|---|
| `incoming` | `claude-sonnet-5-5` | `between_tools` (Sonnet) / `adaptive` (Opus) | `low` | 4096 |
| `outgoing` | `claude-sonnet-5-5` | `adaptive` | `medium` | 16000 |
| `hard` (`Alt+Enter`) | `claude-opus-5-5` | `adaptive` | `high` | 32000 |
| `memo` | same as `outgoing` | `adaptive` | `medium` | 16000 |

## File map

```
ig-translate/
  manifest.json
  package.json
  src/
    background.js            service worker: message router, storage, API calls, badge
    lib/lang.js              Hangul checks, language routing
    lib/keys.js              storage keys, hashing, defaults, pruning
    lib/prompts.js           system prompts, schemas, request builders, response parsers
    lib/api.js               fetch wrapper: headers, retry/backoff, error kinds, parse-retry
    lib/preview.js           outgoing preview state machine (pure reducer)
    lib/classify.js          past vs new classification of bubbles
    content/loader.js        classic content script; dynamic-imports main.js
    content/main.js          per-thread wiring: observer, incoming, outgoing, panel
    content/selectors.js     every Instagram selector (filled from the Task 3 spike)
    content/dom.js           read bubbles, render translations, composer get/set
    content/panel.js         thread panel (shadow DOM)
    content/style.css        injected styles
    options/options.html
    options/options.js
  scripts/
    spike-api.mjs            Task 2
    spike-ime.html           Task 3
    sanitize-snapshot.js     Task 3, pasted into DevTools
    eval-fixtures.mjs        Task 22
    fixtures/conversations.json
  tests/
    *.test.js
    fixtures/thread.html     sanitized Instagram snapshot (Task 3)
  docs/
    spike-notes.md           Task 2 and Task 3 findings
```

Commit messages follow `type: summary` and end with the `Co-Authored-By` line from the session's attribution reminder. Run `npm test` before every commit after Task 1.

**Do not push this repo anywhere.** It holds a (sanitized) Instagram DOM snapshot and is personal.

---

# Sprint 1: Scaffold and spikes

### Task 1: Scaffold

**Files:**
- Create: `package.json`, `manifest.json`, `.gitignore`, `tests/smoke.test.js`

**Step 1: Write `package.json`**

```json
{
  "name": "ig-translate",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test \"tests/*.test.js\""
  },
  "devDependencies": {
    "jsdom": "30.1.3"
  }
}
```

**Step 2: Write `manifest.json`**

```json
{
  "manifest_version": 3,
  "name": "ig-translate",
  "version": "0.1.0",
  "description": "Translate Instagram DMs with Claude.",
  "permissions": ["storage"],
  "host_permissions": [
    "https://www.instagram.com/*",
    "https://api.anthropic.com/*"
  ],
  "background": { "service_worker": "src/background.js", "type": "module" },
  "action": { "default_title": "ig-translate" },
  "options_page": "options/options.html",
  "content_scripts": [
    {
      "matches": ["https://www.instagram.com/*"],
      "js": ["src/content/loader.js"],
      "css": ["src/content/style.css"],
      "run_at": "document_idle"
    }
  ],
  "web_accessible_resources": [
    {
      "resources": ["src/content/*.js", "src/lib/*.js"],
      "matches": ["https://www.instagram.com/*"]
    }
  ]
}
```

The content script matches all of `instagram.com`, not only `/direct/*`. Instagram is an SPA, so a user who lands on the feed and clicks into DMs never triggers a `/direct/*` page load. `main.js` activates only while the path is `/direct/t/<id>`.

Content scripts cannot be ES modules. `loader.js` is a classic script that does `import(chrome.runtime.getURL(...))`, which is why those files are web-accessible. `use_dynamic_url` is deliberately NOT set: it has broken dynamic `import()` from content scripts in Chrome. The cost is that a page could detect the extension by probing these URLs, which is acceptable for a personal tool.

**Step 3: Write `.gitignore`**

```
node_modules/
```

**Step 4: Write `tests/smoke.test.js`**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('manifest is valid JSON with MV3', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(m.manifest_version, 3);
  assert.equal(m.background.type, 'module');
});
```

**Step 5: Install and run**

Run: `npm install && npm test`
Expected: 1 test, PASS.

**Step 6: Commit**

```bash
git add package.json package-lock.json manifest.json .gitignore tests/smoke.test.js
git commit -m "chore: scaffold MV3 extension and test runner"
```

---

### Task 2: API spike

Settles the `[UNVERIFIED]` items. Needs a real key in `ANTHROPIC_API_KEY`. Ask the user to export it in their shell. Never write the key to a file.

**Files:**
- Create: `scripts/spike-api.mjs`, `docs/spike-notes.md`

**Step 1: Write `scripts/spike-api.mjs`**

```js
// Usage: ANTHROPIC_API_KEY=... node scripts/spike-api.mjs
const key = process.env.ANTHROPIC_API_KEY;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }

const schema = {
  type: 'object',
  properties: { translation: { type: 'string' }, back_translation: { type: 'string' } },
  required: ['translation', 'back_translation'],
  additionalProperties: false,
};
const user = 'Translate to English, casual texting style: "야 어제 거기 진짜 미쳤더라 ㅋㅋ 다음에 또 가자"';

const variants = {
  'sonnet between_tools low + format': { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools' }, effort: 'low', max_tokens: 4096, format: true },
  'sonnet adaptive medium + format':   { model: 'claude-sonnet-5-5', thinking: { type: 'adaptive' }, effort: 'medium', max_tokens: 16000, format: true },
  'opus adaptive high + format':       { model: 'claude-opus-5-5', thinking: { type: 'adaptive' }, effort: 'high', max_tokens: 32000, format: true },
  'opus between_tools low':            { model: 'claude-opus-5-5', thinking: { type: 'between_tools' }, effort: 'low', max_tokens: 4096, format: true },
  'sonnet adaptive medium, no format': { model: 'claude-sonnet-5-5', thinking: { type: 'adaptive' }, effort: 'medium', max_tokens: 16000, format: false },
};

async function run(name, v, extraHeaders = {}) {
  const body = {
    model: v.model,
    max_tokens: v.max_tokens,
    thinking: v.thinking,
    output_config: { effort: v.effort, ...(v.format ? { format: { type: 'json_schema', schema } } : {}) },
    messages: [{ role: 'user', content: v.format ? user : user + '\nReply as JSON {"translation":..., "back_translation":...}' }],
  };
  const t0 = Date.now();
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  const ms = Date.now() - t0;
  const text = (json.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
  const types = (json.content || []).map(b => b.type).join(',');
  console.log(`\n== ${name}  [${res.status}] ${ms}ms  blocks=${types}  stop=${json.stop_reason}`);
  console.log(res.ok ? text : JSON.stringify(json.error));
}

for (const [name, v] of Object.entries(variants)) await run(name, v);

// Simulate an extension-origin request.
const sv = variants['sonnet between_tools low + format'];
await run('origin chrome-extension, WITHOUT browser header', sv, { origin: 'chrome-extension://abcdefghijklmnop' });
await run('origin chrome-extension, WITH browser header', sv, {
  origin: 'chrome-extension://abcdefghijklmnop',
  'anthropic-dangerous-direct-browser-access': 'true',
});
```

**Step 2: Run it**

Run: `node scripts/spike-api.mjs`
Expected: a status line and output for each of the 7 variants.

**Step 3: Record the findings in `docs/spike-notes.md`**

Write a section `## API spike (2026-10-27)` covering:
- status and latency for each variant
- whether `format` worked with adaptive thinking
- whether Opus accepts `between_tools`
- whether the extension-origin request needs the browser header

**Step 4: Decision gate (update the code below in this plan only if needed)**

- If `format` + adaptive returned 400: in Task 7 set `useFormat: false` for the `outgoing`, `hard` and `memo` profiles. The parser already accepts a JSON object found in plain text.
- If Opus rejected `between_tools`: no change. `thinkingFor()` already gives Opus `adaptive`.
- If Opus accepted it: still no change (YAGNI).
- If the origin request failed WITH the header: stop and report BLOCKED. Direct calls from the extension would not work, and the design needs revisiting.

**Step 5: Commit**

```bash
git add scripts/spike-api.mjs docs/spike-notes.md
git commit -m "spike: verify thinking, effort, structured output, browser origin"
```

---

### Task 3: DOM and IME spike (manual, Claude in Chrome)

**Safety rules for this task (read before starting):**
- Never press Enter or click Send in an Instagram composer.
- Never dispatch synthetic key events into the Instagram composer. Every text change is reverted before leaving the page.
- The user picks which thread to open. Ask them.

**Files:**
- Create: `scripts/spike-ime.html`, `scripts/sanitize-snapshot.js`, `tests/fixtures/thread.html`
- Modify: `docs/spike-notes.md`

**Step 1: Write `scripts/spike-ime.html`**

This is a local page, so a test keypress cannot send anything.

```html
<!doctype html>
<meta charset="utf-8">
<title>IME Enter spike</title>
<div id="ed" contenteditable="true" style="border:1px solid #888;min-height:3em;padding:8px"></div>
<pre id="log"></pre>
<script>
  const ed = document.getElementById('ed');
  const log = (s) => { document.getElementById('log').textContent += s + '\n'; };
  for (const t of ['keydown', 'keyup', 'compositionstart', 'compositionend', 'beforeinput']) {
    ed.addEventListener(t, (e) => log(`${t} key=${e.key ?? ''} code=${e.keyCode ?? ''} isComposing=${e.isComposing ?? ''} data=${e.data ?? ''} text="${ed.innerText}"`), true);
  }
</script>
```

**Step 2: The user runs the IME test**

Ask the user to open `file:///home/cyan/projects/ig-translate/scripts/spike-ime.html` and type `안녕` with the system Korean IME. They press Enter while `녕` is still composing, then type `하이` and press Enter after the composition is committed (for example after a space). Copy the log into `docs/spike-notes.md` under `## IME Enter`.

The question to answer: when Enter is pressed mid-composition, does Chrome fire one keydown (`isComposing=true`), or that plus a second keydown with `isComposing=false`? Task 18's handler covers both cases. Record which one happens.

**Step 3: Find the selectors on the live page**

1. Load the Claude in Chrome tools in one ToolSearch call (`tabs_context_mcp`, `tabs_create_mcp`, `navigate`, `read_page`, `javascript_tool`, `find`).
2. Open `https://www.instagram.com/direct/inbox/` in a new tab. Ask the user which thread to open, and open it.
3. Use `read_page` and `javascript_tool` to find a stable selector for each of:
   - the scrollable message list container (`threadRoot`)
   - one message row/bubble (`messageRow`)
   - the text element inside a bubble (`messageText`)
   - how to tell **me** from **partner** for a row: alignment, an aria label, a container attribute, or something else. Prefer `role`, `aria-*` and structural relations; avoid hashed class names.
   - the composer contenteditable (`composer`), most likely `div[role="textbox"][contenteditable="true"]`
4. For each selector, record in `docs/spike-notes.md` the selector string, the evidence for it, and how many matches it gets on the page.

**Step 4: Composer write test (no send)**

Run this in the page with `javascript_tool`:

```js
const el = document.querySelector('div[role="textbox"][contenteditable="true"]'); // use the selector found above
el.focus();
document.execCommand('selectAll', false);
document.execCommand('insertText', false, 'igt spike test');
```

Check two things:
- The text shows up in the composer.
- Instagram's state follows. The send button or icon changes, as it does when the user types. Use `find` / `read_page`.

Then clear it the same way: `selectAll`, then `document.execCommand('delete', false)`. Confirm the composer is empty and the send control is back to idle.

If `insertText` does not update Instagram's state, try a synthetic paste:

```js
const dt = new DataTransfer();
dt.setData('text/plain', 'igt spike test');
el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
```

Record which method works. If neither works, stop and report BLOCKED.

The `javascript_tool` runs in the page's main world; the extension's content script runs in an isolated world. Both share the DOM, and `execCommand` produces real input events, so a pass here carries over. Task 17's live check confirms it from the isolated world.

**Step 5: Sanitized snapshot**

Write `scripts/sanitize-snapshot.js`, run it in the page, and save its output as `tests/fixtures/thread.html`.

```js
// Paste into the Instagram thread page. Returns sanitized HTML of the message list.
(() => {
  const ROOT_SELECTOR = '__FILL_FROM_STEP_3__';
  const root = document.querySelector(ROOT_SELECTOR).cloneNode(true);
  let n = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const texts = [];
  while (walker.nextNode()) texts.push(walker.currentNode);
  for (const t of texts) if (t.nodeValue.trim()) t.nodeValue = `msg ${++n}`;
  for (const el of root.querySelectorAll('img, video, source')) {
    el.removeAttribute('src'); el.removeAttribute('srcset'); el.removeAttribute('alt');
  }
  for (const el of root.querySelectorAll('[aria-label]')) {
    // aria labels can contain names; keep only the structural ones noted in spike-notes
    if (!/^(Message|Send|Like)/i.test(el.getAttribute('aria-label'))) el.setAttribute('aria-label', 'x');
  }
  for (const el of root.querySelectorAll('a[href]')) el.setAttribute('href', '#');
  return root.outerHTML;
})();
```

Adjust the `aria-label` keep-list to the labels the selectors from Step 3 depend on. Then open the saved file and grep it for real names or message words, and confirm there are none.

In `docs/spike-notes.md`, record the expected values for the snapshot:
- number of message rows
- for each row: me/partner, and whether it has a text element

Task 13 asserts these values.

**Step 6: Fill in `selectors.js` placeholders in this plan**

Edit Task 13 in this plan file, replacing the `__FILL__` markers with the strings found here.

**Step 7: Commit**

```bash
git add scripts/spike-ime.html scripts/sanitize-snapshot.js tests/fixtures/thread.html docs/spike-notes.md docs/plans/2026-10-27-ig-translate.md
git commit -m "spike: Instagram DOM selectors, composer write method, IME Enter behaviour"
```

---

# Sprint 2: Core libraries (TDD)

### Task 4: `lang.js`

**Files:**
- Create: `src/lib/lang.js`
- Test: `tests/lang.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasHangul, isKoreanOnly, incomingTarget, resolveOutputLang, latestPartnerLang } from '../src/lib/lang.js';

test('hasHangul', () => {
  assert.equal(hasHangul('hello'), false);
  assert.equal(hasHangul('ㅋㅋ ok'), true);
  assert.equal(hasHangul('안녕'), true);
});

test('isKoreanOnly ignores emoji, digits, punctuation', () => {
  assert.equal(isKoreanOnly('안녕 ㅋㅋ 😂 3시!'), true);
  assert.equal(isKoreanOnly('안녕 hi'), false);
  assert.equal(isKoreanOnly('😂'), false);
  assert.equal(isKoreanOnly('привет'), false);
});

test('incomingTarget', () => {
  assert.equal(incomingTarget('ko', 'en'), null);
  assert.equal(incomingTarget('en', 'en'), 'ko');
  assert.equal(incomingTarget('en', 'ko'), 'ko');
  assert.equal(incomingTarget('ru', 'en'), 'en');
  assert.equal(incomingTarget('ru', 'ko'), 'ko');
  assert.equal(incomingTarget('ja', 'ko'), 'ko');
});

test('resolveOutputLang', () => {
  assert.equal(resolveOutputLang({ outputLang: 'ru', partnerLang: 'en' }), 'ru');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: 'ru' }), 'ru');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: null }), 'en');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: 'ko' }), 'en');
});

test('latestPartnerLang picks last non-Korean partner message', () => {
  const r = [
    { from: 'partner', src_lang: 'en' },
    { from: 'me', src_lang: 'ru' },
    { from: 'partner', src_lang: 'ru' },
    { from: 'partner', src_lang: 'ko' },
  ];
  assert.equal(latestPartnerLang(r), 'ru');
  assert.equal(latestPartnerLang([]), null);
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/lang.test.js`
Expected: FAIL, cannot find module `../src/lib/lang.js`.

**Step 3: Implement `src/lib/lang.js`**

```js
const HANGUL = /[ᄀ-ᇿ㄰-㆏가-힯]/;
const HANGUL_G = /[ᄀ-ᇿ㄰-㆏가-힯]/g;

export function hasHangul(s) {
  return HANGUL.test(s);
}

// Hangul present and no letters from any other script.
export function isKoreanOnly(s) {
  return hasHangul(s) && !/\p{L}/u.test(s.replace(HANGUL_G, ''));
}

// Target language for an incoming message, or null if it stays as is.
// otherTarget is the per-thread toggle for non-English languages: 'ko' | 'en'.
export function incomingTarget(srcLang, otherTarget) {
  if (srcLang === 'ko') return null;
  if (srcLang === 'en') return 'ko';
  return otherTarget;
}

export function resolveOutputLang(thread) {
  if (thread.outputLang && thread.outputLang !== 'auto') return thread.outputLang;
  if (thread.partnerLang && thread.partnerLang !== 'ko') return thread.partnerLang;
  return 'en';
}

// results: oldest first, each { from: 'me' | 'partner', src_lang }.
export function latestPartnerLang(results) {
  for (let i = results.length - 1; i >= 0; i--) {
    const r = results[i];
    if (r.from === 'partner' && r.src_lang && r.src_lang !== 'ko') return r.src_lang;
  }
  return null;
}

export const LANG_NAMES = {
  ko: 'Korean', en: 'English', ru: 'Russian', es: 'Spanish', ja: 'Japanese',
  zh: 'Chinese', fr: 'French', de: 'German', uk: 'Ukrainian', pt: 'Portuguese',
};

export const langName = (code) => LANG_NAMES[code] || code;
```

**Step 4: Run, expect PASS**

Run: `node --test tests/lang.test.js`
Expected: 5 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/lang.js tests/lang.test.js
git commit -m "feat: language routing helpers"
```

---

### Task 5: `keys.js`

**Files:**
- Create: `src/lib/keys.js`
- Test: `tests/keys.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { threadIdFromPath, threadKey, cacheKey, sentKey, expiredKeys, PRUNE_MS, withThreadDefaults } from '../src/lib/keys.js';

test('threadIdFromPath', () => {
  assert.equal(threadIdFromPath('/direct/t/1234567/'), '1234567');
  assert.equal(threadIdFromPath('/direct/t/abc'), 'abc');
  assert.equal(threadIdFromPath('/direct/inbox/'), null);
  assert.equal(threadIdFromPath('/'), null);
});

test('threadKey', () => assert.equal(threadKey('42'), 't:42'));

test('cacheKey is stable and depends on every part', async () => {
  const a = await cacheKey('t1', 'hi', 'ko');
  assert.match(a, /^c:[0-9a-f]{64}$/);
  assert.equal(a, await cacheKey('t1', 'hi', 'ko'));
  assert.notEqual(a, await cacheKey('t2', 'hi', 'ko'));
  assert.notEqual(a, await cacheKey('t1', 'hi', 'en'));
  assert.notEqual(a, await cacheKey('t1', 'hi!', 'ko'));
});

test('sentKey', async () => {
  const a = await sentKey('t1', 'see you');
  assert.match(a, /^s:[0-9a-f]{64}$/);
  assert.notEqual(a, await sentKey('t1', 'see you!'));
});

test('expiredKeys only prunes old c: and s: entries', () => {
  const now = 1_000_000_000_000;
  const all = {
    settings: { ts: 0 },
    't:1': { ts: 0 },
    'c:old': { ts: now - PRUNE_MS - 1 },
    'c:new': { ts: now - 1000 },
    's:old': { ts: now - PRUNE_MS - 1 },
    'c:bad': {},
  };
  assert.deepEqual(expiredKeys(all, now).sort(), ['c:old', 's:old']);
});

test('withThreadDefaults fills missing fields from settings defaults', () => {
  const t = withThreadDefaults({ memo: 'bro' }, { otherTarget: 'en', pastMode: 'below', newMode: 'below' });
  assert.equal(t.memo, 'bro');
  assert.equal(t.otherTarget, 'en');
  assert.equal(t.outputLang, 'auto');
  assert.equal(t.enabled, true);
  assert.equal(t.partnerLang, null);
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/keys.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/keys.js`**

```js
export const PRUNE_MS = 90 * 24 * 60 * 60 * 1000;

export const DEFAULT_SETTINGS = {
  apiKey: '',
  models: {
    incoming: 'claude-sonnet-5-5',
    outgoing: 'claude-sonnet-5-5',
    hard: 'claude-opus-5-5',
  },
  threadDefaults: { otherTarget: 'ko', pastMode: 'replace', newMode: 'below' },
};

const THREAD_BASE = { memo: '', partnerLang: null, outputLang: 'auto', enabled: true };

export function withThreadDefaults(stored, threadDefaults) {
  return { ...THREAD_BASE, ...DEFAULT_SETTINGS.threadDefaults, ...threadDefaults, ...stored };
}

export function threadIdFromPath(pathname) {
  const m = pathname.match(/^\/direct\/t\/([^/]+)/);
  return m ? m[1] : null;
}

export const threadKey = (id) => `t:${id}`;

async function sha256hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function cacheKey(threadId, text, otherTarget) {
  return 'c:' + (await sha256hex(JSON.stringify([threadId, text, otherTarget])));
}

export async function sentKey(threadId, text) {
  return 's:' + (await sha256hex(JSON.stringify([threadId, text])));
}

export function expiredKeys(all, now) {
  return Object.entries(all)
    .filter(([k, v]) => (k.startsWith('c:') || k.startsWith('s:')) && typeof v?.ts === 'number' && now - v.ts > PRUNE_MS)
    .map(([k]) => k);
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/keys.test.js`
Expected: 6 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/keys.js tests/keys.test.js
git commit -m "feat: storage keys, hashing, defaults, pruning"
```

---

### Task 6: `api.js`

**Files:**
- Create: `src/lib/api.js`
- Test: `tests/api.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { callClaude, callJson, ApiError } from '../src/lib/api.js';

const noSleep = async () => {};
function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    const r = responses.shift();
    if (r instanceof Error) throw r;
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      headers: new Map(Object.entries(r.headers || {})),
      json: async () => r.body,
    };
  };
  fn.calls = calls;
  return fn;
}

test('sends required headers and no sampling params', async () => {
  const f = fakeFetch([{ status: 200, body: { content: [] } }]);
  await callClaude({ model: 'm' }, 'KEY', { fetchImpl: f, sleep: noSleep });
  const h = f.calls[0].init.headers;
  assert.equal(h['x-api-key'], 'KEY');
  assert.equal(h['anthropic-version'], '2023-06-01');
  assert.equal(h['anthropic-dangerous-direct-browser-access'], 'true');
  const body = JSON.parse(f.calls[0].init.body);
  assert.equal('temperature' in body, false);
});

test('missing key throws nokey without calling fetch', async () => {
  const f = fakeFetch([]);
  await assert.rejects(callClaude({}, '', { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'nokey');
  assert.equal(f.calls.length, 0);
});

test('retries 529 twice then fails as overloaded', async () => {
  const f = fakeFetch([{ status: 529, body: {} }, { status: 529, body: {} }, { status: 529, body: {} }]);
  await assert.rejects(callClaude({}, 'K', { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'overloaded');
  assert.equal(f.calls.length, 3);
});

test('429 honours retry-after then succeeds', async () => {
  const waits = [];
  const f = fakeFetch([{ status: 429, headers: { 'retry-after': '3' }, body: {} }, { status: 200, body: { ok: 1 } }]);
  const r = await callClaude({}, 'K', { fetchImpl: f, sleep: async (ms) => waits.push(ms) });
  assert.deepEqual(r, { ok: 1 });
  assert.deepEqual(waits, [3000]);
});

test('spend-limit 429 does not retry', async () => {
  const f = fakeFetch([{ status: 429, body: { error: { message: 'cap', details: { error_code: 'enforced_spend_limit_reached' } } } }]);
  await assert.rejects(callClaude({}, 'K', { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'spend_limit');
  assert.equal(f.calls.length, 1);
});

test('401 is auth, no retry', async () => {
  const f = fakeFetch([{ status: 401, body: { error: { message: 'bad key' } } }]);
  await assert.rejects(callClaude({}, 'K', { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'auth' && e.message === 'bad key');
  assert.equal(f.calls.length, 1);
});

test('network error retries then fails as network', async () => {
  const f = fakeFetch([new TypeError('x'), new TypeError('x'), new TypeError('x')]);
  await assert.rejects(callClaude({}, 'K', { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'network');
  assert.equal(f.calls.length, 3);
});

test('callJson re-requests once on parse error', async () => {
  const f = fakeFetch([{ status: 200, body: { n: 1 } }, { status: 200, body: { n: 2 } }]);
  let seen = 0;
  const parse = (resp) => { seen++; if (resp.n === 1) throw new ApiError('parse', 'bad'); return resp.n; };
  assert.equal(await callJson({}, 'K', parse, { fetchImpl: f, sleep: noSleep }), 2);
  assert.equal(seen, 2);
});

test('callJson gives up after second parse error', async () => {
  const f = fakeFetch([{ status: 200, body: {} }, { status: 200, body: {} }]);
  const parse = () => { throw new ApiError('parse', 'bad'); };
  await assert.rejects(callJson({}, 'K', parse, { fetchImpl: f, sleep: noSleep }), (e) => e.kind === 'parse');
  assert.equal(f.calls.length, 2);
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/api.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/api.js`**

```js
export const API_URL = 'https://api.anthropic.com/v1/messages';

// kind: nokey | auth | spend_limit | rate | overloaded | server | bad_request | network | refused | parse
export class ApiError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

const RETRYABLE = new Set(['rate', 'overloaded', 'server', 'network']);
const backoff = (attempt) => 1000 * 2 ** attempt;
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

function classify(status, body) {
  if (status === 401 || status === 403) return 'auth';
  if (status === 429) {
    return body?.error?.details?.error_code === 'enforced_spend_limit_reached' ? 'spend_limit' : 'rate';
  }
  if (status === 529) return 'overloaded';
  if (status >= 500) return 'server';
  return 'bad_request';
}

export async function callClaude(body, apiKey, { fetchImpl = fetch, sleep = realSleep, retries = 2, timeoutMs = 90000 } = {}) {
  if (!apiKey) throw new ApiError('nokey', 'No API key set');
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetchImpl(API_URL, {
        method: 'POST',
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
          'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      if (attempt < retries) { await sleep(backoff(attempt)); continue; }
      throw new ApiError('network', String(e?.message || e));
    }
    if (res.ok) return res.json();
    const errBody = await res.json().catch(() => ({}));
    const kind = classify(res.status, errBody);
    if (RETRYABLE.has(kind) && attempt < retries) {
      const ra = Number(res.headers.get('retry-after'));
      await sleep(ra > 0 ? ra * 1000 : backoff(attempt));
      continue;
    }
    throw new ApiError(kind, errBody?.error?.message || `HTTP ${res.status}`, res.status);
  }
}

// parse(resp) returns the value or throws ApiError('parse'). One re-request on parse failure.
export async function callJson(body, apiKey, parse, opts) {
  try {
    return parse(await callClaude(body, apiKey, opts));
  } catch (e) {
    if (e.kind !== 'parse') throw e;
    return parse(await callClaude(body, apiKey, opts));
  }
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/api.test.js`
Expected: 9 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/api.js tests/api.test.js
git commit -m "feat: API client with retry, backoff, error kinds"
```

---

### Task 7: `prompts.js`

**Files:**
- Create: `src/lib/prompts.js`
- Test: `tests/prompts.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  PROFILES, thinkingFor, buildIncomingRequest, buildOutgoingRequest, buildMemoRequest,
  parseIncoming, parseOutgoing, parseMemo,
} from '../src/lib/prompts.js';

const ctx = [{ from: 'partner', text: 'hey' }, { from: 'me', text: 'yo' }];

test('thinkingFor: Sonnet off = between_tools, Opus always adaptive', () => {
  assert.deepEqual(thinkingFor('claude-sonnet-5-5', true), { type: 'between_tools' });
  assert.deepEqual(thinkingFor('claude-opus-5-5', true), { type: 'adaptive' });
  assert.deepEqual(thinkingFor('claude-sonnet-5-5', false), { type: 'adaptive' });
});

test('incoming request shape', () => {
  const b = buildIncomingRequest({
    model: 'claude-sonnet-5-5', memo: 'old friend', context: ctx, otherTarget: 'en',
    items: [{ id: '0', text: 'привет' }],
  });
  assert.equal(b.model, 'claude-sonnet-5-5');
  assert.deepEqual(b.thinking, { type: 'between_tools' });
  assert.equal(b.output_config.effort, 'low');
  assert.equal(b.output_config.format.type, 'json_schema');
  assert.equal(b.max_tokens, PROFILES.incoming.max_tokens);
  for (const k of ['temperature', 'top_p', 'top_k']) assert.equal(k in b, false);
  const u = b.messages[0].content;
  assert.match(u, /TARGET_FOR_OTHER: English/);
  assert.match(u, /old friend/);
  assert.match(u, /FRIEND: hey/);
  assert.match(u, /ME: yo/);
  assert.match(u, /привет/);
});

test('outgoing request uses profile and target', () => {
  const b = buildOutgoingRequest({ model: 'claude-opus-5-5', profile: 'hard', memo: '', context: ctx, korean: '내일 보자', lang: 'ru' });
  assert.deepEqual(b.thinking, { type: 'adaptive' });
  assert.equal(b.output_config.effort, 'high');
  assert.match(b.messages[0].content, /TARGET: Russian/);
  assert.match(b.messages[0].content, /내일 보자/);
});

test('memo request', () => {
  const b = buildMemoRequest({ model: 'claude-sonnet-5-5', context: ctx });
  assert.equal(b.output_config.effort, 'medium');
  assert.match(b.messages[0].content, /FRIEND: hey/);
});

const resp = (text, stop = 'end_turn') => ({
  stop_reason: stop,
  content: [{ type: 'thinking', thinking: '' }, { type: 'text', text }],
});

test('parseIncoming maps ids and skips thinking blocks', () => {
  const r = parseIncoming(resp('{"items":[{"id":"0","src_lang":"ru","translation":"hi"}]}'));
  assert.deepEqual(r, { '0': { src_lang: 'ru', translation: 'hi' } });
});

test('parseOutgoing accepts JSON embedded in prose (no-format fallback)', () => {
  const r = parseOutgoing(resp('Here:\n{"translation":"see you","back_translation":"또 봐"}'));
  assert.deepEqual(r, { translation: 'see you', back_translation: '또 봐' });
});

test('parse errors', () => {
  assert.throws(() => parseOutgoing(resp('nope')), (e) => e.kind === 'parse');
  assert.throws(() => parseOutgoing(resp('{"translation":"x"}')), (e) => e.kind === 'parse');
  assert.throws(() => parseOutgoing(resp('{}', 'max_tokens')), (e) => e.kind === 'parse');
  assert.throws(() => parseOutgoing(resp('{}', 'refusal')), (e) => e.kind === 'refused');
});

test('parseMemo', () => {
  assert.equal(parseMemo(resp('{"memo":"close friend, teases a lot"}')), 'close friend, teases a lot');
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/prompts.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/prompts.js`**

```js
import { ApiError } from './api.js';
import { langName } from './lang.js';

// useFormat: set false for a profile if the Task 2 spike showed format + adaptive thinking fails.
export const PROFILES = {
  incoming: { thinkingOff: true, effort: 'low', max_tokens: 4096, useFormat: true },
  outgoing: { thinkingOff: false, effort: 'medium', max_tokens: 16000, useFormat: true },
  hard: { thinkingOff: false, effort: 'high', max_tokens: 32000, useFormat: true },
  memo: { thinkingOff: false, effort: 'medium', max_tokens: 16000, useFormat: true },
};

export function thinkingFor(model, off) {
  return off && model.startsWith('claude-sonnet') ? { type: 'between_tools' } : { type: 'adaptive' };
}

const INCOMING_SYSTEM = `You translate Instagram direct messages between friends for a Korean speaker.
For every listed message:
- Detect its language and report it as an ISO 639-1 code in src_lang ("en", "ru", "ko", ...).
- Korean: return the original text unchanged.
- English: translate into Korean.
- Any other language: translate into the language given as TARGET_FOR_OTHER.
Style:
- Keep the register. Casual stays casual. Korean output uses casual speech (banmal) unless the memo says otherwise.
- Render slang and internet speak as natural equivalents, not literal glosses.
- Keep emoji, names, @handles, URLs and line breaks as they are.
- Use the recent conversation and the thread memo to resolve pronouns, jokes and references.
- Translate only the listed messages, never the context.
Return one item per listed message with the same id.`;

const OUTGOING_SYSTEM = `You help a Korean speaker write Instagram direct messages to a friend.
Translate the Korean draft into the TARGET language so it reads like a native speaker texting a friend.
- Korean often drops the subject. Use the recent conversation and the memo to decide who does what to whom.
- Match the register and tone of the conversation. Casual stays casual. Keep emoji.
- Do not add content, greetings, sign-offs or explanations that are not in the draft.
- back_translation: translate your output back into natural Korean, close enough that the writer can check the meaning.`;

const MEMO_SYSTEM = `Read this Instagram DM conversation and write a short memo, at most 5 lines in English, that helps a translator.
Cover: who the friend is to the user, the tone and register both sides use, nicknames, running jokes or recurring topics.
Only state what the conversation supports.`;

const INCOMING_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, src_lang: { type: 'string' }, translation: { type: 'string' } },
        required: ['id', 'src_lang', 'translation'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
};

const OUTGOING_SCHEMA = {
  type: 'object',
  properties: { translation: { type: 'string' }, back_translation: { type: 'string' } },
  required: ['translation', 'back_translation'],
  additionalProperties: false,
};

const MEMO_SCHEMA = {
  type: 'object',
  properties: { memo: { type: 'string' } },
  required: ['memo'],
  additionalProperties: false,
};

const formatContext = (context) =>
  context.map((m) => `${m.from === 'me' ? 'ME' : 'FRIEND'}: ${m.text}`).join('\n') || '(none)';

function request(model, profileName, system, userText, schema) {
  const p = PROFILES[profileName];
  const output_config = { effort: p.effort };
  let content = userText;
  if (p.useFormat) output_config.format = { type: 'json_schema', schema };
  else content += `\n\nReply with only a JSON object matching this schema:\n${JSON.stringify(schema)}`;
  return {
    model,
    max_tokens: p.max_tokens,
    thinking: thinkingFor(model, p.thinkingOff),
    output_config,
    system,
    messages: [{ role: 'user', content }],
  };
}

export function buildIncomingRequest({ model, memo, context, items, otherTarget }) {
  const text = [
    `TARGET_FOR_OTHER: ${langName(otherTarget)}`,
    `THREAD MEMO:\n${memo || '(none)'}`,
    `RECENT CONVERSATION (oldest first):\n${formatContext(context)}`,
    `MESSAGES TO TRANSLATE:\n${JSON.stringify(items.map(({ id, text }) => ({ id, text })))}`,
  ].join('\n\n');
  return request(model, 'incoming', INCOMING_SYSTEM, text, INCOMING_SCHEMA);
}

export function buildOutgoingRequest({ model, profile, memo, context, korean, lang }) {
  const text = [
    `TARGET: ${langName(lang)}`,
    `THREAD MEMO:\n${memo || '(none)'}`,
    `RECENT CONVERSATION (oldest first):\n${formatContext(context)}`,
    `KOREAN DRAFT:\n${korean}`,
  ].join('\n\n');
  return request(model, profile, OUTGOING_SYSTEM, text, OUTGOING_SCHEMA);
}

export function buildMemoRequest({ model, context }) {
  return request(model, 'memo', MEMO_SYSTEM, `CONVERSATION (oldest first):\n${formatContext(context)}`, MEMO_SCHEMA);
}

function extractJson(resp) {
  if (resp.stop_reason === 'refusal') throw new ApiError('refused', 'Model refused');
  if (resp.stop_reason === 'max_tokens') throw new ApiError('parse', 'Output truncated');
  const text = (resp.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
  try {
    return JSON.parse(text);
  } catch {
    const m = text.match(/\{[\s\S]*\}/);
    if (m) { try { return JSON.parse(m[0]); } catch {} }
    throw new ApiError('parse', 'Response is not JSON');
  }
}

export function parseIncoming(resp) {
  const j = extractJson(resp);
  if (!Array.isArray(j.items)) throw new ApiError('parse', 'items missing');
  const out = {};
  for (const it of j.items) {
    if (typeof it.id !== 'string' || typeof it.translation !== 'string') throw new ApiError('parse', 'bad item');
    out[it.id] = { src_lang: it.src_lang, translation: it.translation };
  }
  return out;
}

export function parseOutgoing(resp) {
  const j = extractJson(resp);
  if (typeof j.translation !== 'string' || typeof j.back_translation !== 'string') {
    throw new ApiError('parse', 'translation fields missing');
  }
  return { translation: j.translation, back_translation: j.back_translation };
}

export function parseMemo(resp) {
  const j = extractJson(resp);
  if (typeof j.memo !== 'string') throw new ApiError('parse', 'memo missing');
  return j.memo;
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/prompts.test.js`
Expected: 8 tests PASS.

**Step 5: Apply the Task 2 decision gate**

If the spike recorded that format + adaptive fails, set `useFormat: false` on `outgoing`, `hard` and `memo` now, then re-run the tests. Add one test asserting `output_config.format` is absent for `outgoing` in that case.

**Step 6: Commit**

```bash
git add src/lib/prompts.js tests/prompts.test.js
git commit -m "feat: prompts, schemas, request builders, parsers"
```

---

### Task 8: `preview.js` (outgoing state machine)

**Files:**
- Create: `src/lib/preview.js`
- Test: `tests/preview.test.js`

State: `{ mode: 'idle' | 'translating' | 'preview', korean, profile, lang, reqId }`.
`reduce(state, event)` returns `{ state, effect }`. `effect` is one of:
- `{ type: 'pass' }`: let the key event through
- `{ type: 'block' }`: preventDefault and do nothing
- `{ type: 'translate', reqId, korean, profile, lang }`: call the background
- `{ type: 'show', translation, back_translation, profile, lang }`: write the translation into the composer
- `{ type: 'restore', korean }`: write the Korean back into the composer
- `{ type: 'sent', korean }`: let Enter through and record the sent message
- `{ type: 'fail', message }`: show the error, composer untouched
- `{ type: 'none' }`

`lang: null` in a translate effect means "resolve from the thread".

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, reduce } from '../src/lib/preview.js';

const run = (events, s = initial()) => {
  const effects = [];
  for (const e of events) { const r = reduce(s, e); s = r.state; effects.push(r.effect); }
  return { s, effects };
};

test('non-Hangul Enter passes through', () => {
  const { s, effects } = run([{ type: 'enter', text: 'hello', hard: false }]);
  assert.equal(s.mode, 'idle');
  assert.deepEqual(effects[0], { type: 'pass' });
});

test('Hangul Enter starts translation; second Enter while pending is blocked', () => {
  const { s, effects } = run([
    { type: 'enter', text: '내일 봐', hard: false },
    { type: 'enter', text: '내일 봐', hard: false },
  ]);
  assert.equal(s.mode, 'translating');
  assert.equal(effects[0].type, 'translate');
  assert.equal(effects[0].korean, '내일 봐');
  assert.equal(effects[0].profile, 'outgoing');
  assert.equal(effects[0].lang, null);
  assert.deepEqual(effects[1], { type: 'block' });
});

test('result shows preview, Enter sends with Korean original', () => {
  const a = reduce(initial(), { type: 'enter', text: '내일 봐', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'see u tmrw', back_translation: '내일 봐', lang: 'en' });
  assert.equal(b.state.mode, 'preview');
  assert.equal(b.effect.type, 'show');
  const c = reduce(b.state, { type: 'enter', text: 'see u tmrw!', hard: false });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'sent', korean: '내일 봐' });
});

test('stale result is ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId + 99, translation: 'x', back_translation: 'y', lang: 'en' });
  assert.equal(b.state.mode, 'translating');
  assert.deepEqual(b.effect, { type: 'none' });
});

test('Alt+Enter outside preview uses hard profile', () => {
  const { effects } = run([{ type: 'enter', text: '가자', hard: true }]);
  assert.equal(effects[0].profile, 'hard');
});

test('Alt+Enter inside preview re-translates stored Korean with hard', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: "let's go", back_translation: '가자', lang: 'en' });
  const c = reduce(b.state, { type: 'enter', text: "let's go (edited)", hard: true });
  assert.equal(c.state.mode, 'translating');
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.korean, '가자');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'en');
});

test('language change in preview re-translates with same profile', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: true });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: "let's go", back_translation: '가자', lang: 'en' });
  const c = reduce(b.state, { type: 'lang', lang: 'ru' });
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'ru');
  assert.equal(c.effect.korean, '가자');
});

test('Esc in preview restores Korean', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'go', back_translation: '가자', lang: 'en' });
  const c = reduce(b.state, { type: 'esc' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'restore', korean: '가자' });
});

test('Esc while translating cancels; late result ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'esc' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'none' });
  const c = reduce(b.state, { type: 'result', reqId: a.effect.reqId, translation: 'go', back_translation: '가자', lang: 'en' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'none' });
});

test('failure returns to idle with Korean intact', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'fail', reqId: a.effect.reqId, message: 'overloaded' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'fail', message: 'overloaded' });
});

test('Esc in idle passes; reset always returns idle', () => {
  assert.deepEqual(reduce(initial(), { type: 'esc' }).effect, { type: 'pass' });
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  assert.equal(reduce(a.state, { type: 'reset' }).state.mode, 'idle');
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/preview.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/preview.js`**

```js
import { hasHangul } from './lang.js';

export const initial = () => ({ mode: 'idle', korean: null, profile: null, lang: null, reqId: 0 });

function translate(s, korean, profile, lang) {
  const reqId = s.reqId + 1;
  return {
    state: { mode: 'translating', korean, profile, lang, reqId },
    effect: { type: 'translate', reqId, korean, profile, lang },
  };
}

const idle = (s) => ({ ...s, mode: 'idle', korean: null, profile: null, lang: null });

export function reduce(s, e) {
  switch (e.type) {
    case 'enter': {
      const profile = e.hard ? 'hard' : 'outgoing';
      if (s.mode === 'translating') return { state: s, effect: { type: 'block' } };
      if (s.mode === 'preview') {
        if (e.hard) return translate(s, s.korean, 'hard', s.lang);
        return { state: idle(s), effect: { type: 'sent', korean: s.korean } };
      }
      if (!hasHangul(e.text)) return { state: s, effect: { type: 'pass' } };
      return translate(s, e.text, profile, null);
    }
    case 'result':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return {
        state: { ...s, mode: 'preview', lang: e.lang },
        effect: { type: 'show', translation: e.translation, back_translation: e.back_translation, profile: s.profile, lang: e.lang },
      };
    case 'fail':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return { state: idle(s), effect: { type: 'fail', message: e.message } };
    case 'lang':
      if (s.mode !== 'preview') return { state: s, effect: { type: 'none' } };
      return translate(s, s.korean, s.profile, e.lang);
    case 'esc':
      if (s.mode === 'preview') return { state: idle(s), effect: { type: 'restore', korean: s.korean } };
      if (s.mode === 'translating') return { state: idle(s), effect: { type: 'none' } };
      return { state: s, effect: { type: 'pass' } };
    case 'reset':
      return { state: idle(s), effect: { type: 'none' } };
    default:
      return { state: s, effect: { type: 'none' } };
  }
}
```

`reqId` is never reset by `idle()`, so a result that arrives after a cancel or reset can never match a later request.

**Step 4: Run, expect PASS**

Run: `node --test tests/preview.test.js`
Expected: 11 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/preview.js tests/preview.test.js
git commit -m "feat: outgoing preview state machine"
```

---

### Task 9: `classify.js` (past vs new)

**Files:**
- Create: `src/lib/classify.js`
- Test: `tests/classify.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyAdded } from '../src/lib/classify.js';

const known = (set) => (x) => set.has(x);

test('appended below last known = fresh, prepended above = past', () => {
  const r = classifyAdded(['h1', 'h2', 'a', 'b', 'n1'], known(new Set(['a', 'b'])));
  assert.deepEqual(r, { past: ['h1', 'h2'], fresh: ['n1'] });
});

test('unknown between known ones = past', () => {
  const r = classifyAdded(['a', 'x', 'b'], known(new Set(['a', 'b'])));
  assert.deepEqual(r, { past: ['x'], fresh: [] });
});

test('nothing known = all fresh (caller handles initial scan separately)', () => {
  assert.deepEqual(classifyAdded(['a', 'b'], known(new Set())), { past: [], fresh: ['a', 'b'] });
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/classify.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/classify.js`**

```js
// ordered: bubbles in DOM order (top to bottom). isKnown: already-seen check.
// Unknown bubbles after the last known one are fresh arrivals; all others are back-filled history.
export function classifyAdded(ordered, isKnown) {
  let lastKnown = -1;
  ordered.forEach((x, i) => { if (isKnown(x)) lastKnown = i; });
  const past = [];
  const fresh = [];
  ordered.forEach((x, i) => { if (!isKnown(x)) (i > lastKnown ? fresh : past).push(x); });
  return { past, fresh };
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/classify.test.js`
Expected: 3 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/classify.js tests/classify.test.js
git commit -m "feat: classify added bubbles as past or fresh"
```

---

# Sprint 3: Background and options

### Task 10: `background.js`

The background service worker is not unit-tested directly; it is glue over the tested libraries. Keep logic out of it. Message types and replies:

| `type` | request | reply `data` |
|---|---|---|
| `getThread` | `{threadId}` | thread object with defaults |
| `setThread` | `{threadId, patch}` | updated thread |
| `incoming` | `{threadId, context, items:[{id, text, from}]}` | `{ [id]: {src_lang, translation} \| null }` (null = leave as is) |
| `outgoing` | `{threadId, context, korean, profile, lang}` | `{translation, back_translation, lang, model}` |
| `sent` | `{threadId, text, korean}` | `true` |
| `lookupSent` | `{threadId, texts}` | `{ [text]: korean }` |
| `suggestMemo` | `{threadId, context}` | `memo` string |
| `badge` | `{text}` | `true` |
| `openOptions` | `{}` | `true` |

Every reply is `{ok: true, data}` or `{ok: false, error: {kind, message}}`.

**Files:**
- Create: `src/background.js`

**Step 1: Write `src/background.js`**

```js
import { callJson, ApiError } from './lib/api.js';
import {
  buildIncomingRequest, buildOutgoingRequest, buildMemoRequest,
  parseIncoming, parseOutgoing, parseMemo,
} from './lib/prompts.js';
import { incomingTarget, resolveOutputLang, latestPartnerLang } from './lib/lang.js';
import { DEFAULT_SETTINGS, withThreadDefaults, threadKey, cacheKey, sentKey, expiredKeys } from './lib/keys.js';

const store = chrome.storage.local;
const BATCH = 40;

async function getSettings() {
  const { settings } = await store.get('settings');
  return {
    ...DEFAULT_SETTINGS, ...settings,
    models: { ...DEFAULT_SETTINGS.models, ...settings?.models },
    threadDefaults: { ...DEFAULT_SETTINGS.threadDefaults, ...settings?.threadDefaults },
  };
}

async function getThread(threadId, settings) {
  const k = threadKey(threadId);
  const got = await store.get(k);
  return withThreadDefaults(got[k] || {}, (settings || (await getSettings())).threadDefaults);
}

async function setThread(threadId, patch) {
  const k = threadKey(threadId);
  const got = await store.get(k);
  const next = { ...(got[k] || {}), ...patch };
  await store.set({ [k]: next });
  return getThread(threadId);
}

async function incoming({ threadId, context, items }) {
  const settings = await getSettings();
  const thread = await getThread(threadId, settings);
  const keys = await Promise.all(items.map((it) => cacheKey(threadId, it.text, thread.otherTarget)));
  const hits = await store.get(keys);
  const out = {};
  const misses = [];
  items.forEach((it, i) => {
    const h = hits[keys[i]];
    if (h) out[it.id] = h; else misses.push({ it, key: keys[i] });
  });

  for (let i = 0; i < misses.length; i += BATCH) {
    const chunk = misses.slice(i, i + BATCH);
    const body = buildIncomingRequest({
      model: settings.models.incoming, memo: thread.memo, context,
      otherTarget: thread.otherTarget, items: chunk.map((m) => m.it),
    });
    const res = await callJson(body, settings.apiKey, parseIncoming);
    const writes = {};
    for (const { it, key } of chunk) {
      const r = res[it.id];
      if (!r) continue;
      const entry = { src_lang: r.src_lang, translation: r.translation, ts: Date.now() };
      writes[key] = entry;
      out[it.id] = entry;
    }
    await store.set(writes);
  }

  const ordered = items.filter((it) => out[it.id]).map((it) => ({ from: it.from, src_lang: out[it.id].src_lang }));
  const lang = latestPartnerLang(ordered);
  if (lang && lang !== thread.partnerLang) await setThread(threadId, { partnerLang: lang });

  const data = {};
  for (const it of items) {
    const r = out[it.id];
    data[it.id] = r && incomingTarget(r.src_lang, thread.otherTarget) ? { src_lang: r.src_lang, translation: r.translation } : null;
  }
  return data;
}

async function outgoing({ threadId, context, korean, profile, lang }) {
  const settings = await getSettings();
  const thread = await getThread(threadId, settings);
  const target = lang || resolveOutputLang(thread);
  const model = profile === 'hard' ? settings.models.hard : settings.models.outgoing;
  const body = buildOutgoingRequest({ model, profile, memo: thread.memo, context, korean, lang: target });
  const r = await callJson(body, settings.apiKey, parseOutgoing);
  return { ...r, lang: target, model };
}

async function suggestMemo({ context }) {
  const settings = await getSettings();
  return callJson(buildMemoRequest({ model: settings.models.outgoing, context }), settings.apiKey, parseMemo);
}

async function sent({ threadId, text, korean }) {
  await store.set({ [await sentKey(threadId, text)]: { korean, ts: Date.now() } });
  return true;
}

async function lookupSent({ threadId, texts }) {
  const keys = await Promise.all(texts.map((t) => sentKey(threadId, t)));
  const got = await store.get(keys);
  const out = {};
  texts.forEach((t, i) => { if (got[keys[i]]) out[t] = got[keys[i]].korean; });
  return out;
}

const handlers = {
  getThread: ({ threadId }) => getThread(threadId),
  setThread: ({ threadId, patch }) => setThread(threadId, patch),
  incoming, outgoing, suggestMemo, sent, lookupSent,
  badge: async ({ text }, sender) => { await chrome.action.setBadgeText({ text, tabId: sender.tab?.id }); return true; },
  openOptions: async () => { await chrome.runtime.openOptionsPage(); return true; },
};

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const h = handlers[msg?.type];
  if (!h) return false;
  Promise.resolve(h(msg, sender))
    .then((data) => sendResponse({ ok: true, data }))
    .catch((e) => sendResponse({ ok: false, error: { kind: e instanceof ApiError ? e.kind : 'internal', message: String(e?.message || e) } }));
  return true;
});

async function prune() {
  const all = await store.get(null);
  const dead = expiredKeys(all, Date.now());
  if (dead.length) await store.remove(dead);
}
chrome.runtime.onStartup.addListener(prune);
chrome.runtime.onInstalled.addListener(prune);
```

Notes:
- The cache stores every result, including Korean no-ops (`src_lang: 'ko'`). A Korean message then costs one call ever, and `incomingTarget` turns it into `null` on the way out.
- English results are the same whatever the toggle says, but their cache key includes the toggle. Flipping the toggle re-requests them once. Accepted (spec review note).

**Step 2: Syntax check**

Run: `node --check src/background.js && npm test`
Expected: no syntax error; all tests PASS.

**Step 3: Commit**

```bash
git add src/background.js
git commit -m "feat: background router, cache, thread state, API calls"
```

---

### Task 11: Options page

**Files:**
- Create: `options/options.html`, `options/options.js`

**Step 1: Write `options/options.html`**

```html
<!doctype html>
<meta charset="utf-8">
<title>ig-translate options</title>
<style>
  body { font: 14px system-ui, sans-serif; max-width: 520px; margin: 24px auto; padding: 0 16px; }
  label { display: block; margin: 14px 0 4px; font-weight: 600; }
  input, select { width: 100%; padding: 6px; box-sizing: border-box; }
  #saved { color: green; margin-left: 8px; }
</style>
<h1>ig-translate</h1>
<label for="apiKey">Anthropic API key</label>
<input id="apiKey" type="password" autocomplete="off">
<label for="incoming">Incoming model</label>
<select id="incoming"></select>
<label for="outgoing">Outgoing model (Enter)</label>
<select id="outgoing"></select>
<label for="hard">Hard model (Alt+Enter)</label>
<select id="hard"></select>
<label for="otherTarget">Default: non-English incoming to</label>
<select id="otherTarget"><option value="ko">Korean</option><option value="en">English</option></select>
<label for="pastMode">Default: past messages</label>
<select id="pastMode"><option value="replace">Replace text</option><option value="below">Below bubble</option></select>
<label for="newMode">Default: new messages</label>
<select id="newMode"><option value="below">Below bubble</option><option value="replace">Replace text</option></select>
<p><button id="save">Save</button><span id="saved"></span></p>
<script type="module" src="options.js"></script>
```

**Step 2: Write `options/options.js`**

```js
import { DEFAULT_SETTINGS } from '../src/lib/keys.js';

const MODELS = ['claude-sonnet-5-5', 'claude-opus-5-5'];
const $ = (id) => document.getElementById(id);

for (const id of ['incoming', 'outgoing', 'hard']) {
  for (const m of MODELS) $(id).add(new Option(m, m));
}

const { settings = {} } = await chrome.storage.local.get('settings');
const s = {
  ...DEFAULT_SETTINGS, ...settings,
  models: { ...DEFAULT_SETTINGS.models, ...settings.models },
  threadDefaults: { ...DEFAULT_SETTINGS.threadDefaults, ...settings.threadDefaults },
};
$('apiKey').value = s.apiKey;
for (const id of ['incoming', 'outgoing', 'hard']) $(id).value = s.models[id];
for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).value = s.threadDefaults[id];

$('save').onclick = async () => {
  await chrome.storage.local.set({
    settings: {
      apiKey: $('apiKey').value.trim(),
      models: { incoming: $('incoming').value, outgoing: $('outgoing').value, hard: $('hard').value },
      threadDefaults: { otherTarget: $('otherTarget').value, pastMode: $('pastMode').value, newMode: $('newMode').value },
    },
  });
  $('saved').textContent = 'Saved';
  setTimeout(() => { $('saved').textContent = ''; }, 1500);
};
```

**Step 3: Commit**

```bash
git add options/
git commit -m "feat: options page"
```

---

### Task 12: Load unpacked and smoke-test the background (manual)

**Step 1:** Create a stub `src/content/loader.js` containing only `// filled in Task 14`, and an empty `src/content/style.css`, so the manifest loads.

**Step 2:** Ask the user to open `chrome://extensions`, enable Developer mode, click "Load unpacked", and pick `/home/cyan/projects/ig-translate`. Then open the extension's options page, paste the API key, and save. The key is typed by the user, never by Claude.

**Step 3:** Ask the user to right-click the options page, choose Inspect, and run this in its console. Service workers forbid `import()`, so use the options page. It has the same `chrome-extension://` origin as the service worker, and it sends the request through the background exactly as the content script will.

```js
const r = await chrome.runtime.sendMessage({ type: 'outgoing', threadId: 'smoke', context: [], korean: '내일 보자', profile: 'outgoing', lang: 'en' });
console.log(r);
```

Expected: `{ok: true, data: {translation, back_translation, lang: 'en', model: 'claude-sonnet-5-5'}}`. This confirms a real extension-origin request works end to end through the background router. If CORS or 4xx fails here, check the `anthropic-dangerous-direct-browser-access` header first. Record the result in `docs/spike-notes.md`.

**Step 4: Confirm content-script dynamic import**

Temporarily replace the stub `src/content/loader.js` with:

```js
(async () => {
  const m = await import(chrome.runtime.getURL('src/lib/lang.js'));
  console.log('[igt] dynamic import ok', m.hasHangul('안녕'));
})();
```

Reload the extension, then open any `instagram.com` page. The page console should show `[igt] dynamic import ok true`. If it throws, stop and report BLOCKED. The fallback is listing every content file as classic scripts in `content_scripts.js`, which changes Tasks 13 to 18. Record the result in `docs/spike-notes.md`, then put the stub back.

**Step 5: Commit**

```bash
git add src/content/loader.js src/content/style.css docs/spike-notes.md
git commit -m "chore: loadable extension, background smoke test recorded"
```

---

# Sprint 4: Incoming translation in the page

### Task 13: `selectors.js` and `dom.js` readers (snapshot tests)

**Files:**
- Create: `src/content/selectors.js`, `src/content/dom.js`
- Test: `tests/dom.test.js`

**Step 1: Write `src/content/selectors.js` with the Task 3 findings**

```js
// Every Instagram DOM assumption lives here. When Instagram changes, re-run the Task 3 spike and edit this file.
export const SEL = {
  threadRoot: '__FILL__',   // scrollable message list
  messageRow: '__FILL__',   // one bubble/row, relative to threadRoot
  messageText: '__FILL__',  // text element inside a row
  composer: 'div[role="textbox"][contenteditable="true"]', // confirm in Task 3
};

// Returns 'me' | 'partner' for a row element. Implement the rule recorded in docs/spike-notes.md.
export function senderOf(row) {
  __FILL__;
}
```

**Step 2: Write the failing test** (the expected numbers come from `docs/spike-notes.md`, Task 3 Step 5)

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { readMessages, findThreadRoot } from '../src/content/dom.js';

const html = readFileSync(new URL('./fixtures/thread.html', import.meta.url), 'utf8');
const doc = new JSDOM(`<body>${html}</body>`).window.document;

const EXPECTED_ROWS = __FILL__;          // from spike-notes
const EXPECTED_SENDERS = __FILL__;       // e.g. ['partner','partner','me',...] for text rows, from spike-notes

test('finds thread root', () => {
  assert.ok(findThreadRoot(doc));
});

test('reads text rows with sender, in order', () => {
  const msgs = readMessages(findThreadRoot(doc));
  assert.equal(msgs.length, EXPECTED_ROWS);
  assert.deepEqual(msgs.map((m) => m.from), EXPECTED_SENDERS);
  for (const m of msgs) assert.match(m.text, /^msg \d+/);
});
```

**Step 3: Run, expect FAIL**

Run: `node --test tests/dom.test.js`
Expected: FAIL, module `dom.js` not found.

**Step 4: Implement the reader part of `src/content/dom.js`**

```js
import { SEL, senderOf } from './selectors.js';

export const findThreadRoot = (doc) => doc.querySelector(SEL.threadRoot);
export const findComposer = (doc) => doc.querySelector(SEL.composer);

// Text bubbles only, top to bottom. Rows without a text element (media, stickers) are skipped.
export function readMessages(root) {
  const out = [];
  for (const row of root.querySelectorAll(SEL.messageRow)) {
    const textEl = row.querySelector(SEL.messageText);
    const text = textEl?.innerText ?? textEl?.textContent ?? '';
    if (!text.trim()) continue;
    out.push({ row, textEl, text: text.trim(), from: senderOf(row) });
  }
  return out;
}
```

jsdom has no layout, so `innerText` is undefined there and `textContent` is used. In Chrome `innerText` keeps line breaks.

Check that `SEL.messageText` cannot match the `.igt-tr` elements this extension inserts (Task 14), or translations would be read back as messages.

If `senderOf` depends on layout (`getBoundingClientRect`), it cannot run in jsdom. In that case, find a structural signal instead. If none exists, test `senderOf` live in Task 17 only and drop `EXPECTED_SENDERS` from this test, noting why in spike-notes.

**Step 5: Run, expect PASS**

Run: `node --test tests/dom.test.js`
Expected: 2 tests PASS.

**Step 6: Commit**

```bash
git add src/content/selectors.js src/content/dom.js tests/dom.test.js
git commit -m "feat: Instagram selectors and message reader with snapshot test"
```

---

### Task 14: Rendering helpers and loader

**Files:**
- Modify: `src/content/dom.js` (append)
- Modify: `src/content/loader.js`, `src/content/style.css`
- Test: `tests/dom.test.js` (append)

**Step 1: Append failing tests to `tests/dom.test.js`**

```js
import { renderTranslation, clearTranslation, setHoverOriginal } from '../src/content/dom.js';

function bubble() {
  const d = new JSDOM('<div class="row"><span class="t">привет</span></div>').window.document;
  return { row: d.querySelector('.row'), textEl: d.querySelector('.t') };
}

test('below mode adds a sibling, keeps original visible', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'below');
  assert.equal(m.row.querySelector('.igt-tr').textContent, 'hi');
  assert.equal(m.textEl.hasAttribute('data-igt-hide'), false);
});

test('replace mode hides original, shows translation with original on hover', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'replace');
  assert.equal(m.textEl.getAttribute('data-igt-hide'), '');
  const tr = m.row.querySelector('.igt-tr');
  assert.equal(tr.textContent, 'hi');
  assert.equal(tr.title, 'привет');
});

test('render is idempotent and clear restores', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'replace');
  renderTranslation(m, 'hello', 'below');
  assert.equal(m.row.querySelectorAll('.igt-tr').length, 1);
  assert.equal(m.textEl.hasAttribute('data-igt-hide'), false);
  clearTranslation(m);
  assert.equal(m.row.querySelectorAll('.igt-tr').length, 0);
});

test('setHoverOriginal sets title on own bubble', () => {
  const m = bubble();
  setHoverOriginal(m, '안녕');
  assert.equal(m.textEl.title, '안녕');
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/dom.test.js`
Expected: the new tests FAIL, exports missing.

**Step 3: Append to `src/content/dom.js`**

```js
// We never change text inside Instagram's own nodes: React may re-render and throw.
// We hide the original via a data attribute (React leaves unknown attributes alone) and add a sibling.
export function renderTranslation(m, translation, mode) {
  clearTranslation(m);
  const tr = m.textEl.ownerDocument.createElement('div');
  tr.className = `igt-tr igt-${mode}`;
  tr.textContent = translation;
  if (mode === 'replace') {
    tr.title = m.text ?? m.textEl.textContent;
    m.textEl.setAttribute('data-igt-hide', '');
  }
  m.textEl.after(tr);
}

export function clearTranslation(m) {
  m.textEl.removeAttribute('data-igt-hide');
  m.textEl.parentElement?.querySelectorAll(':scope > .igt-tr').forEach((n) => n.remove());
}

export function renderRetry(m, onClick) {
  clearTranslation(m);
  const b = m.textEl.ownerDocument.createElement('button');
  b.className = 'igt-tr igt-retry';
  b.textContent = '⟳';
  b.title = 'Translation failed, click to retry';
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  m.textEl.after(b);
}

export function setHoverOriginal(m, korean) {
  m.textEl.title = korean;
}
```

The test helper bubbles have no `m.text`, so `renderTranslation` falls back to `textContent`.

**Step 4: Write `src/content/style.css`**

```css
[data-igt-hide] { display: none !important; }
.igt-tr { font-size: 0.85em; opacity: 0.85; margin-top: 2px; white-space: pre-wrap; }
.igt-tr.igt-replace { font-size: inherit; opacity: 1; margin-top: 0; }
.igt-retry { background: none; border: 0; cursor: pointer; color: inherit; padding: 0 4px; }
.igt-composer-note { font-size: 12px; padding: 4px 12px; opacity: 0.8; }
.igt-composer-note.igt-error { color: #e5484d; opacity: 1; }
.igt-chip { border: 1px solid currentColor; border-radius: 10px; padding: 0 6px; margin-left: 6px; cursor: pointer; background: none; color: inherit; font-size: 11px; }
```

**Step 5: Write `src/content/loader.js`**

```js
// Classic content script. Content scripts cannot be ES modules, so load the real entry dynamically.
(async () => {
  try {
    const { start } = await import(chrome.runtime.getURL('src/content/main.js'));
    start();
  } catch (e) {
    console.error('[igt] failed to load', e);
  }
})();
```

**Step 6: Run, expect PASS**

Run: `npm test`
Expected: all PASS.

**Step 7: Commit**

```bash
git add src/content/dom.js src/content/loader.js src/content/style.css tests/dom.test.js
git commit -m "feat: translation rendering helpers, loader, styles"
```

---

### Task 15: `main.js`, thread lifecycle and incoming

**Files:**
- Create: `src/content/main.js`

**Step 1: Write `src/content/main.js` (incoming part; Task 18 adds outgoing)**

```js
import { threadIdFromPath } from '../lib/keys.js';
import { isKoreanOnly } from '../lib/lang.js';
import { classifyAdded } from '../lib/classify.js';
import { findThreadRoot, readMessages, renderTranslation, renderRetry, setHoverOriginal, clearTranslation } from './dom.js';

const CONTEXT_N = 30;
const DEBOUNCE_MS = 400;

export const ask = async (msg) => {
  const r = await chrome.runtime.sendMessage(msg);
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
};

let current = null; // { threadId, thread, root, observer, known: WeakSet, timer, pending: [], ...outgoing state }
let keyBannerShown = false;

export function start() {
  let lastPath = null;
  const tick = () => {
    if (location.pathname === lastPath) return;
    lastPath = location.pathname;
    teardown();
    const id = threadIdFromPath(location.pathname);
    if (id) waitForThread(id);
  };
  tick();
  setInterval(tick, 500); // SPA navigation: poll the path; cheap and reliable
}

function teardown() {
  if (!current) return;
  current.observer?.disconnect();
  clearTimeout(current.timer);
  current.onTeardown?.forEach((f) => f());
  current = null;
}

// The message list renders after navigation; wait up to 10 s, then mark the selectors broken.
function waitForThread(threadId, tries = 0) {
  const root = findThreadRoot(document);
  if (root && readMessages(root).length) return initThread(threadId, root);
  if (tries >= 20) {
    if (root) return initThread(threadId, root); // empty thread is fine
    ask({ type: 'badge', text: '!' }).catch(() => {});
    console.warn('[igt] thread root not found; extension inactive on this page');
    return;
  }
  setTimeout(() => {
    if (threadIdFromPath(location.pathname) === threadId) waitForThread(threadId, tries + 1);
  }, 500);
}

async function initThread(threadId, root) {
  const thread = await ask({ type: 'getThread', threadId });
  ask({ type: 'badge', text: '' }).catch(() => {});
  current = { threadId, thread, root, known: new WeakSet(), pending: [], timer: null, onTeardown: [] };

  const msgs = readMessages(root);
  msgs.forEach((m) => current.known.add(m.row));
  if (thread.enabled) {
    translate(msgs, thread.pastMode);
    hoverSent(msgs);
  }

  current.observer = new MutationObserver(() => onMutate(threadId));
  current.observer.observe(root, { childList: true, subtree: true });

  // Hook for Task 18/19 (outgoing, panel).
  for (const f of initHooks) f(current);
}

export const initHooks = [];

function onMutate(threadId) {
  if (!current || current.threadId !== threadId) return;
  clearTimeout(current.timer);
  current.timer = setTimeout(() => {
    if (!current || current.threadId !== threadId) return;
    const msgs = readMessages(current.root);
    const { past, fresh } = classifyAdded(msgs, (m) => current.known.has(m.row));
    for (const m of [...past, ...fresh]) current.known.add(m.row);
    if (!current.thread.enabled) return;
    translate(past, current.thread.pastMode);
    translate(fresh, current.thread.newMode);
    hoverSent([...past, ...fresh]);
  }, DEBOUNCE_MS);
}

export function contextFor(root) {
  return readMessages(root).slice(-CONTEXT_N).map(({ from, text }) => ({ from, text }));
}

async function translate(msgs, mode) {
  const todo = msgs.filter((m) => m.from === 'partner' && !isKoreanOnly(m.text));
  if (!todo.length) return;
  const threadId = current.threadId;
  const items = todo.map((m, i) => ({ id: String(i), text: m.text, from: m.from }));
  try {
    const data = await ask({ type: 'incoming', threadId, context: contextFor(current.root), items });
    if (current?.threadId !== threadId) return;
    todo.forEach((m, i) => { const r = data[String(i)]; if (r) renderTranslation(m, r.translation, mode); });
    // partnerLang may have changed; refresh the cached thread state
    current.thread = await ask({ type: 'getThread', threadId });
  } catch (e) {
    if (current?.threadId !== threadId) return;
    if (e.kind === 'nokey' || e.kind === 'auth') return showKeyBanner(e.kind);
    todo.forEach((m) => renderRetry(m, () => translate([m], mode)));
  }
}

async function hoverSent(msgs) {
  const mine = msgs.filter((m) => m.from === 'me');
  if (!mine.length) return;
  const threadId = current.threadId;
  try {
    const map = await ask({ type: 'lookupSent', threadId, texts: mine.map((m) => m.text) });
    if (current?.threadId !== threadId) return;
    for (const m of mine) if (map[m.text]) setHoverOriginal(m, map[m.text]);
  } catch {}
}

// Re-render everything after a panel toggle change.
export function rerender() {
  if (!current) return;
  const msgs = readMessages(current.root);
  msgs.forEach(clearTranslation);
  if (current.thread.enabled) translate(msgs, current.thread.pastMode); // cache makes this cheap
}

function showKeyBanner(kind) {
  if (keyBannerShown) return;
  keyBannerShown = true;
  const b = document.createElement('div');
  b.style.cssText = 'position:fixed;top:12px;right:12px;z-index:99999;background:#222;color:#fff;padding:10px 14px;border-radius:8px;font:13px system-ui;cursor:pointer';
  b.textContent = kind === 'nokey' ? 'ig-translate: set your API key (click)' : 'ig-translate: API key rejected (click)';
  b.onclick = () => { ask({ type: 'openOptions' }).catch(() => {}); b.remove(); };
  document.body.appendChild(b);
}

export const getCurrent = () => current;
```

Notes:
- `rerender` applies `pastMode` to every visible message, so after a toggle change, new ones that arrived earlier switch to past mode. Accepted: a toggle change is a deliberate re-layout.
- Our own `.igt-tr` insertions trigger the observer. `readMessages` returns the same rows, they are all `known`, so nothing re-translates.
- If Instagram recreates a row node, it is unknown again and gets translated again. The cache makes that free; display mode may follow the classification of its position.

**Step 2: Syntax check and tests**

Run: `node --check src/content/main.js && npm test`
Expected: no error; tests PASS.

**Step 3: Commit**

```bash
git add src/content/main.js
git commit -m "feat: thread lifecycle and incoming translation"
```

---

### Task 16: Thread panel

**Files:**
- Create: `src/content/panel.js`
- Modify: `src/content/main.js` (register the hook)

**Step 1: Write `src/content/panel.js`**

```js
import { ask, rerender, getCurrent, contextFor } from './main.js';
import { LANG_NAMES } from '../lib/lang.js';

export function mountPanel(cur) {
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;right:16px;bottom:96px;z-index:99998';
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      button.fab { width: 36px; height: 36px; border-radius: 18px; border: 0; background: #3a3a3c; color: #fff; cursor: pointer; font: 600 13px system-ui; }
      .p { display: none; position: absolute; right: 0; bottom: 44px; width: 280px; background: #1c1c1e; color: #f2f2f7; border-radius: 10px; padding: 12px; font: 13px system-ui; box-shadow: 0 4px 16px #0006; }
      .p.open { display: block; }
      label { display: flex; justify-content: space-between; align-items: center; margin: 6px 0; gap: 8px; }
      select, textarea { background: #2c2c2e; color: inherit; border: 1px solid #48484a; border-radius: 6px; font: inherit; }
      textarea { width: 100%; box-sizing: border-box; height: 90px; margin-top: 4px; }
      .row { display: flex; gap: 6px; margin-top: 6px; }
      .row button { flex: 1; background: #2c2c2e; color: inherit; border: 1px solid #48484a; border-radius: 6px; padding: 4px; cursor: pointer; }
    </style>
    <button class="fab" title="ig-translate">T</button>
    <div class="p">
      <label>Translate <input type="checkbox" id="enabled"></label>
      <label>Reply in <select id="outputLang"></select></label>
      <label>Other languages to <select id="otherTarget"><option value="ko">Korean</option><option value="en">English</option></select></label>
      <label>Past messages <select id="pastMode"><option value="replace">Replace</option><option value="below">Below</option></select></label>
      <label>New messages <select id="newMode"><option value="below">Below</option><option value="replace">Replace</option></select></label>
      <div>Memo</div>
      <textarea id="memo" placeholder="Who they are, tone, nicknames, running jokes"></textarea>
      <div class="row"><button id="suggest">Suggest memo</button><button id="saveMemo">Save memo</button></div>
    </div>`;
  const $ = (id) => shadow.getElementById(id);
  const out = $('outputLang');
  out.add(new Option('Auto', 'auto'));
  for (const [code, name] of Object.entries(LANG_NAMES)) if (code !== 'ko') out.add(new Option(name, code));

  const fill = (t) => {
    $('enabled').checked = t.enabled;
    out.value = t.outputLang;
    for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).value = t[id];
    $('memo').value = t.memo;
  };
  fill(cur.thread);

  shadow.querySelector('.fab').onclick = () => {
    shadow.querySelector('.p').classList.toggle('open');
    fill(getCurrent()?.thread || cur.thread); // pick up partnerLang/outputLang changes
  };

  const save = async (patch, rerenderAfter) => {
    const c = getCurrent();
    if (!c) return;
    c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch });
    if (rerenderAfter) rerender();
  };
  $('enabled').onchange = () => save({ enabled: $('enabled').checked }, true);
  out.onchange = () => save({ outputLang: out.value }, false);
  for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).onchange = () => save({ [id]: $(id).value }, true);
  $('saveMemo').onclick = () => save({ memo: $('memo').value }, false);
  $('suggest').onclick = async () => {
    const c = getCurrent();
    if (!c) return;
    $('suggest').disabled = true;
    try {
      $('memo').value = await ask({ type: 'suggestMemo', threadId: c.threadId, context: contextFor(c.root) });
    } catch (e) {
      $('memo').placeholder = `Suggestion failed: ${e.message}`;
    } finally {
      $('suggest').disabled = false;
    }
  };

  document.body.appendChild(host);
  cur.onTeardown.push(() => host.remove());
}
```

Memo suggestion only fills the textarea; nothing is stored until "Save memo".

**Step 2: Register the hook in `start()` in `src/content/main.js`**

Make `start` async and load the panel before the first `tick()`, so the hook exists before any `initThread` runs:

```js
export async function start() {
  const { mountPanel } = await import('./panel.js');
  initHooks.push(mountPanel);
  let lastPath = null;
  // ... rest of the existing body unchanged
}
```

The import is dynamic because `panel.js` imports from `main.js`. By the time `start()` runs, `main.js` has finished evaluating, so the cycle is safe.

**Step 3: Syntax check and tests**

Run: `node --check src/content/panel.js && node --check src/content/main.js && npm test`
Expected: PASS.

**Step 4: Commit**

```bash
git add src/content/panel.js src/content/main.js
git commit -m "feat: per-thread panel with toggles and memo"
```

---

### Task 17: Live check, incoming (manual)

**Safety:** no sending, no typing in the Instagram composer.

**Step 1:** Ask the user to reload the extension at `chrome://extensions` and reload the Instagram tab.

**Step 2:** Using Claude in Chrome, open a thread the user picks that has non-Korean messages. Check:
- [ ] past partner messages are replaced by Korean, with the original on hover
- [ ] own messages are untouched
- [ ] the panel button appears; toggling "Past messages" to Below re-renders
- [ ] toggling "Other languages to" English re-renders non-English messages (for example Russian) in English, while English messages stay Korean
- [ ] scrolling up loads history, and that history is translated in past mode
- [ ] switching to another thread tears down the panel and translations, then sets up the new thread
- [ ] the service worker console has no errors
- [ ] in the panel, `Reply in` is still Auto, and `chrome.storage.local` `t:<id>` shows `partnerLang` set

**Step 3:** Ask the user to have a friend (or a second account) send a message while the thread is open. Check that it is translated **below** the bubble.

**Step 4:** Record pass/fail per item in `docs/spike-notes.md` under `## Live check: incoming`. Fix any selector issue in `selectors.js`, plus the snapshot test if needed. Commit.

```bash
git add -A
git commit -m "test: live incoming check recorded"
```

---

# Sprint 5: Outgoing preview

### Task 18: Composer write helpers and key interception

**Files:**
- Modify: `src/content/dom.js` (append composer helpers)
- Create: `src/content/outgoing.js`
- Modify: `src/content/main.js` (`start()` loads `outgoing.js`, as shown in Task 16)

**Step 1: Append composer helpers to `src/content/dom.js`**

Use the method that worked in Task 3 Step 4. If it was `insertText`:

```js
export function getComposerText(el) {
  return (el.innerText || '').replace(/\n$/, '');
}

export function setComposerText(el, text) {
  el.focus();
  const sel = el.ownerDocument.getSelection();
  sel.selectAllChildren(el);
  if (text) el.ownerDocument.execCommand('insertText', false, text);
  else el.ownerDocument.execCommand('delete', false);
}
```

If the spike found that paste works and `insertText` does not, the body of `setComposerText` becomes: select all, `execCommand('delete')`, then dispatch the `ClipboardEvent('paste')` from Task 3.

**Step 2: Write `src/content/outgoing.js`**

```js
import { initial, reduce } from '../lib/preview.js';
import { hasHangul, langName, LANG_NAMES } from '../lib/lang.js';
import { findComposer, getComposerText, setComposerText } from './dom.js';
import { ask, getCurrent, contextFor } from './main.js';

export function mountOutgoing(cur) {
  let state = initial();
  let note = null;
  let enterAfterComposition = false;

  const composer = () => findComposer(document);

  const showNote = (html, isError) => {
    const c = composer();
    if (!c) return;
    if (!note) {
      note = document.createElement('div');
      note.className = 'igt-composer-note';
      // Insert above the composer's form row so Instagram's own layout stays intact.
      c.closest('form, [role="group"]')?.before(note) ?? c.parentElement.before(note);
    }
    note.classList.toggle('igt-error', !!isError);
    note.replaceChildren(...html);
  };
  const hideNote = () => { note?.remove(); note = null; };

  const chip = (lang) => {
    const b = document.createElement('button');
    b.className = 'igt-chip';
    b.textContent = langName(lang);
    b.title = 'Change target language';
    b.onclick = (e) => {
      e.preventDefault();
      const sel = document.createElement('select');
      sel.className = 'igt-chip';
      for (const [code, name] of Object.entries(LANG_NAMES)) if (code !== 'ko') sel.add(new Option(name, code));
      sel.value = lang;
      sel.onchange = async () => {
        const c = getCurrent();
        if (c) c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch: { outputLang: sel.value } });
        dispatch({ type: 'lang', lang: sel.value });
      };
      b.replaceWith(sel);
      sel.focus();
    };
    return b;
  };

  async function apply(effect) {
    const c = composer();
    switch (effect.type) {
      case 'translate': {
        showNote([document.createTextNode(effect.profile === 'hard' ? 'Translating (Opus)...' : 'Translating...')]);
        try {
          const cur2 = getCurrent();
          const r = await ask({
            type: 'outgoing', threadId: cur2.threadId, context: contextFor(cur2.root),
            korean: effect.korean, profile: effect.profile, lang: effect.lang,
          });
          dispatch({ type: 'result', reqId: effect.reqId, ...r });
        } catch (e) {
          dispatch({ type: 'fail', reqId: effect.reqId, message: e.message });
        }
        break;
      }
      case 'show': {
        if (c) setComposerText(c, effect.translation);
        const model = effect.profile === 'hard' ? 'Opus' : 'Sonnet';
        showNote([document.createTextNode(`${effect.back_translation}  · ${model}`), chip(effect.lang)]);
        break;
      }
      case 'restore':
        if (c) setComposerText(c, effect.korean);
        hideNote();
        break;
      case 'sent': {
        const cur2 = getCurrent();
        const text = c ? getComposerText(c) : '';
        hideNote();
        if (cur2 && text) ask({ type: 'sent', threadId: cur2.threadId, text, korean: effect.korean }).catch(() => {});
        break;
      }
      case 'fail':
        showNote([document.createTextNode(`Translation failed: ${effect.message}`)], true);
        break;
    }
  }

  function dispatch(event) {
    const r = reduce(state, event);
    state = r.state;
    apply(r.effect);
    return r.effect;
  }

  function onKeyDown(e) {
    const c = composer();
    if (!c || !c.contains(e.target)) return;
    if (!getCurrent()?.thread.enabled) return;

    if (e.key === 'Escape') {
      const eff = dispatch({ type: 'esc' });
      if (eff.type !== 'pass') { e.preventDefault(); e.stopImmediatePropagation(); }
      return;
    }
    if (e.key !== 'Enter' || e.shiftKey) return;

    // Korean IME: Enter mid-composition. Block it so Instagram cannot send raw Korean,
    // then handle Enter once the composition is committed.
    if (e.isComposing || e.keyCode === 229) {
      if (state.mode === 'idle' && hasHangul(getComposerText(c))) {
        e.preventDefault(); e.stopImmediatePropagation();
        enterAfterComposition = { hard: e.altKey };
      }
      return;
    }

    const eff = dispatch({ type: 'enter', text: getComposerText(c), hard: e.altKey });
    // 'sent' lets the real Enter through so Instagram sends the composer text itself.
    if (eff.type !== 'pass' && eff.type !== 'sent') { e.preventDefault(); e.stopImmediatePropagation(); }
  }

  function onCompositionEnd() {
    if (!enterAfterComposition) return;
    const { hard } = enterAfterComposition;
    enterAfterComposition = false;
    // Let the committed text land in the composer first.
    setTimeout(() => {
      const c = composer();
      if (c) dispatch({ type: 'enter', text: getComposerText(c), hard });
    }, 0);
  }

  window.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('compositionend', onCompositionEnd, true);
  cur.onTeardown.push(() => {
    window.removeEventListener('keydown', onKeyDown, true);
    window.removeEventListener('compositionend', onCompositionEnd, true);
    dispatch({ type: 'reset' });
    hideNote();
  });
}
```

How this fits the design:
- Listeners sit on `window` in the capture phase, so they run before Instagram's handlers on the composer.
- If the IME spike showed Chrome fires a second, non-composing Enter after the composing one, that second Enter reaches `reduce` while in `translating`, gets `block`, and nothing double-fires.
- With `Alt+Enter`, check in Task 19 that Instagram does not treat `Alt+Enter` as send by itself. Our capture listener blocks it either way, except for `pass`. A non-Hangul `Alt+Enter` passes through untouched, which is fine.

**Step 3: Wire it into `start()` in `src/content/main.js`**

```js
export async function start() {
  const [{ mountPanel }, { mountOutgoing }] = await Promise.all([import('./panel.js'), import('./outgoing.js')]);
  initHooks.push(mountPanel, mountOutgoing);
  let lastPath = null;
  // ... rest unchanged
}
```

**Step 4: Syntax check and tests**

Run: `node --check src/content/outgoing.js && node --check src/content/main.js && npm test`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/content/dom.js src/content/outgoing.js src/content/main.js
git commit -m "feat: outgoing preview flow with IME-safe Enter handling"
```

---

### Task 19: Live check, outgoing (manual, user presses send)

**Safety: the user does every keypress in this task.** Claude only observes with `read_page` and screenshots, and never types into or submits the Instagram composer.

**Step 1:** Reload the extension and the tab. The user opens a thread with a friend who knows about the test, or a second account.

**Step 2:** The user types `내일 몇 시에 볼까?` and presses Enter. Check:
- [ ] composer text becomes the translation in the partner's language
- [ ] the note shows the back-translation, `Sonnet`, and the language chip
- [ ] nothing was sent

**Step 3:** The user presses Esc. Check: the Korean comes back, the note disappears, nothing was sent.

**Step 4:** The user presses Enter again (preview), then `Alt+Enter`. Check: the note says `Opus`, and the translation is replaced.

**Step 5:** The user clicks the chip and picks another language. Check: the text is re-translated, and the panel's `Reply in` now shows that language.

**Step 6:** The user switches `Reply in` back to Auto in the panel, presses Enter (preview), then Enter again to send. Check:
- [ ] exactly one message was sent, in the target language
- [ ] hovering the sent bubble shows the Korean original (after the observer picks it up)

**Step 7:** IME case: the user types a Korean word and presses Enter while the last syllable is still composing. Check: a preview appears, not a send of the raw Korean.

**Step 8:** Failure case: in options, the user replaces the key with `sk-bad` and presses Enter on Korean text. Check: the Korean stays in the composer, an error note appears, and nothing is sent. They then restore the real key.

**Step 9:** Record results in `docs/spike-notes.md` under `## Live check: outgoing`. Fix any failures, then commit.

```bash
git add -A
git commit -m "test: live outgoing check recorded"
```

---

# Sprint 6: Fixture eval

### Task 20: Fixture set and eval script

**Files:**
- Create: `scripts/fixtures/conversations.json`, `scripts/eval-fixtures.mjs`

**Step 1: Write `scripts/fixtures/conversations.json`**

These are invented conversations, not real DMs.

```json
[
  {
    "name": "en casual slang",
    "memo": "college friend, teases a lot",
    "otherTarget": "ko",
    "context": [
      { "from": "partner", "text": "bro you coming tonight or nah" },
      { "from": "me", "text": "maybe lol" }
    ],
    "items": [{ "id": "0", "text": "ngl that party was lowkey mid", "expect_src": "en" }],
    "outgoing": { "korean": "아 미안 오늘은 좀 피곤해서 패스", "lang": "en" }
  },
  {
    "name": "ru informal",
    "memo": "",
    "otherTarget": "en",
    "context": [{ "from": "partner", "text": "Привет! Как дела?" }],
    "items": [{ "id": "0", "text": "Слушай, давай завтра созвонимся, ок?", "expect_src": "ru" }],
    "outgoing": { "korean": "좋아 몇 시가 편해?", "lang": "ru" }
  },
  {
    "name": "es and korean mixed",
    "memo": "met at language exchange",
    "otherTarget": "ko",
    "context": [],
    "items": [
      { "id": "0", "text": "jajaja qué buena onda", "expect_src": "es" },
      { "id": "1", "text": "ㅋㅋㅋ 고마워", "expect_src": "ko" }
    ],
    "outgoing": { "korean": "다음 주에 시간 돼?", "lang": "es" }
  },
  {
    "name": "ja subject drop",
    "memo": "",
    "otherTarget": "ko",
    "context": [{ "from": "me", "text": "I went to the new ramen place" }],
    "items": [{ "id": "0", "text": "え、まじ？どうだった？", "expect_src": "ja" }],
    "outgoing": { "korean": "생각보다 별로였어 국물이 너무 짰어", "lang": "ja" }
  }
]
```

**Step 2: Write `scripts/eval-fixtures.mjs`**

```js
// Usage: ANTHROPIC_API_KEY=... node scripts/eval-fixtures.mjs [--hard]
import { readFileSync } from 'node:fs';
import { callJson } from '../src/lib/api.js';
import { buildIncomingRequest, buildOutgoingRequest, parseIncoming, parseOutgoing } from '../src/lib/prompts.js';

const key = process.env.ANTHROPIC_API_KEY;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }
const hard = process.argv.includes('--hard');
const cases = JSON.parse(readFileSync(new URL('./fixtures/conversations.json', import.meta.url)));
let failures = 0;

for (const c of cases) {
  console.log(`\n=== ${c.name}`);
  const t0 = Date.now();
  const inc = await callJson(buildIncomingRequest({
    model: 'claude-sonnet-5-5', memo: c.memo, context: c.context, otherTarget: c.otherTarget,
    items: c.items.map(({ id, text }) => ({ id, text })),
  }), key, parseIncoming);
  console.log(`incoming ${Date.now() - t0}ms`);
  for (const it of c.items) {
    const r = inc[it.id];
    const ok = r && r.src_lang === it.expect_src;
    if (!ok) failures++;
    console.log(`  [${ok ? 'ok' : 'FAIL'}] ${it.text}\n      -> (${r?.src_lang}) ${r?.translation}`);
  }
  const t1 = Date.now();
  const out = await callJson(buildOutgoingRequest({
    model: hard ? 'claude-opus-5-5' : 'claude-sonnet-5-5', profile: hard ? 'hard' : 'outgoing',
    memo: c.memo, context: c.context, korean: c.outgoing.korean, lang: c.outgoing.lang,
  }), key, parseOutgoing);
  console.log(`outgoing ${Date.now() - t1}ms\n  ${c.outgoing.korean}\n  -> ${out.translation}\n  <- ${out.back_translation}`);
}
console.log(`\n${failures} src_lang failure(s)`);
process.exit(failures ? 1 : 0);
```

**Step 3: Run it**

Run: `node scripts/eval-fixtures.mjs`
Expected: `0 src_lang failure(s)`, plus a latency per call. Show the translations to the user for an eye check.

Run: `node scripts/eval-fixtures.mjs --hard`
Expected: same, with Opus for outgoing.

**Step 4:** If the user flags tone problems, adjust the system prompts in `src/lib/prompts.js`, then re-run Task 7's tests and this script.

**Step 5: Commit**

```bash
git add scripts/fixtures/conversations.json scripts/eval-fixtures.mjs src/lib/prompts.js
git commit -m "test: fixture eval for prompts and parsing"
```
