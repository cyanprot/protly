# ig-translate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use execute-flow to implement this plan task-by-task.

**Goal:** A personal Chrome MV3 extension that translates Instagram web DMs into Korean (or English) and turns Korean drafts into the partner's language through a preview-then-send flow, using the Claude API with conversation context and a per-thread memo.

**Architecture:** Plain ES modules, no build step, loaded unpacked. Pure logic lives in `src/lib/` and is unit-tested with `node --test`. The background service worker owns all storage and every API call. It sends API calls through a Chrome native messaging host: a small stdlib-only Python script that Chrome starts on demand, which reads the API key from disk and calls the Anthropic API. The key never enters the browser. The content script is a thin DOM layer: it reads bubbles, renders translations, intercepts composer keys and hosts the thread panel, and asks the background for everything else via `chrome.runtime.sendMessage`.

**Tech Stack:** Chrome Manifest V3, vanilla JS (ESM), Chrome native messaging, Python 3 stdlib (`urllib`, `unittest`), Anthropic Messages API, Node 22 `node:test`, `jsdom` (dev only, DOM snapshot tests).

**Design doc:** `docs/plans/2026-10-27-ig-translate-design.md` (read it first).

**Why native messaging:** the Task 2 spike showed this organization rejects browser-origin (CORS) API requests: `401 "CORS requests are not allowed for this Organization because of its settings."`. Requests without an `Origin` header succeed. See `docs/spike-notes.md`.

---

## Verified API facts (platform.claude.com docs + Task 2 spike, 2026-10-27)

- Model IDs: `claude-sonnet-5-5`, `claude-opus-5-5`.
- Effort: top-level `output_config: { effort: "low" | "medium" | "high" | "xhigh" | "max" }`. GA, no beta header.
- Thinking on these models:
  - Omitting `thinking` means **adaptive thinking ON**, not off.
  - `{type: "disabled"}` returns 400 on both models.
  - Sonnet 5.5 "off": `thinking: { type: "between_tools" }`, only with effort `high` or lower, no other fields. Spike: 200.
  - Opus 5.5 cannot turn thinking off. Use `thinking: { type: "adaptive" }`. Spike: Opus rejects `between_tools` with 400 `"thinking.type.between_tools" is not supported for this model.`
  - Thinking tokens count toward `max_tokens`. Response `content` has `thinking` blocks before `text` blocks; read only `type === "text"`.
- **Never send `temperature`, `top_p` or `top_k`.** They return 400 under the current API version.
- Structured output: `output_config: { format: { type: "json_schema", schema } }`. No beta header. The JSON is a string inside a `text` block. `stop_reason` `"refusal"` or `"max_tokens"` means the output may not match.
  - Spike: `format` works together with adaptive thinking (Sonnet and Opus). Without `format`, Sonnet wraps the JSON in a ```` ```json ```` fence.
- Headers (sent by the native host, never by the browser): `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, and `anthropic-workspace-id`.
  - The user's key (`~/.config/anthropic/api-key`, `sk-ant-usr-...`) is not workspace-scoped. Without `anthropic-workspace-id` the API returns 400 `"This API key is not scoped to a workspace..."`. The ID is `workspace_id` in `~/.config/anthropic/configs/default.json`.
  - The host sends no `Origin` and no `anthropic-dangerous-direct-browser-access` header.
- Errors:
  - 429 `rate_limit_error` carries a `retry-after` header in seconds. The exception is a 429 with `error.details.error_code === "enforced_spend_limit_reached"`: no `retry-after`, do not retry.
  - 529 `overloaded_error`: retry with backoff.
  - Other statuses: 401 auth, 402 billing, 403 permission, 500 api, 504 timeout.
  - Error body: `{type:"error", error:{type, message}, request_id}`.

## Verified extension and tooling facts (context7, 2026-10-27)

- Extension service workers support static `import` and `importScripts()`, but **not** dynamic `import()` (developer.chrome.com, service worker basics). `background.js` uses static imports only.
- `runtime.onMessage` listener may `return true` and call `sendResponse` later (runtime API reference).
- `web_accessible_resources` entries take `resources`, `matches` and optional `use_dynamic_url` (manifest reference).
- Native messaging (developer.chrome.com, native messaging):
  - User-level host manifest on Linux for Google Chrome: `~/.config/google-chrome/NativeMessagingHosts/<name>.json`. `path` must be absolute. `allowed_origins` lists `chrome-extension://<id>/`.
  - Host names may contain only lowercase alphanumerics, `_` and `.`.
  - Each message is UTF-8 JSON preceded by a 32-bit length in native byte order, on stdin/stdout. Host to Chrome: max 1 MB per message. Chrome to host: max 64 MiB. Debug output goes to stderr, never stdout.
  - `runtime.connectNative()` starts the host and keeps it running until the port closes. An open native port keeps the service worker alive (Chrome 105+), so long API calls are not cut off by the 30 s fetch rule.
  - Common errors: "Specified native messaging host not found", "Access to the specified native messaging host is forbidden" (origin not in `allowed_origins`), "Native host has exited".
- `[UNVERIFIED]` dynamic `import(chrome.runtime.getURL(...))` from a content script. Widely used, but not in the fetched docs. Task 14 Step 6 confirms it before Sprint 4.
- jsdom: `new JSDOM(html).window.document`. jsdom does **not** implement `innerText` (its WebIDL comments it out), so readers fall back to `textContent`.

## Request profiles

| Profile | Model (default) | thinking | effort | max_tokens |
|---|---|---|---|---|
| `incoming` | `claude-sonnet-5-5` | `between_tools` (Sonnet) / `adaptive` (Opus) | `low` | 8192 |
| `outgoing` | `claude-sonnet-5-5` | `adaptive` | `medium` | 16000 |
| `hard` (`Alt+Enter`) | `claude-opus-5-5` | `adaptive` | `high` | 32000 |
| `memo` | same as `outgoing` | `adaptive` | `medium` | 16000 |

## File map

```
ig-translate/
  manifest.json
  package.json
  host/
    ig_translate_host.py     native messaging host: framing, key/workspace from disk, urllib call
    test_host.py             Python unit tests for the host
    install.sh               writes the Chrome host manifest for a given extension ID
  src/
    background.js            service worker: message router, storage, API calls via native host, badge
    lib/lang.js              Hangul checks, language routing
    lib/keys.js              storage keys, hashing, defaults, pruning
    lib/prompts.js           system prompts, schemas, request builders, response parsers
    lib/api.js               transport-agnostic API client: retry/backoff, error kinds, parse-retry
    lib/native.js            native messaging transport: one long-lived port, id-matched replies
    lib/preview.js           outgoing preview state machine (pure reducer)
    lib/classify.js          past vs new classification of bubbles
    content/loader.js        classic content script; dynamic-imports main.js
    content/main.js          per-thread wiring: observer, incoming, hooks, banners
    content/selectors.js     every Instagram selector (filled from the Task 3 spike)
    content/dom.js           read bubbles, render translations, composer get/set
    content/panel.js         thread panel (shadow DOM)
    content/outgoing.js      composer key interception and preview UI
    content/style.css        injected styles
  options/
    options.html             models and per-thread defaults (no API key)
    options.js
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
    spike-notes.md           spike and live-check findings
```

Commit messages follow `type: summary` and end with the `Co-Authored-By` line from the session's attribution reminder. Run `npm test` before every commit after Task 1. After Task 10, also run `python3 -I host/test_host.py`.

**Do not push this repo anywhere.** It holds a (sanitized) Instagram DOM snapshot and is personal.

**Never print the API key** in any command output. Read it only inside commands, for example `ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)"`.

---

# Sprint 1: Scaffold and spikes

### Task 1: Scaffold

Done (commit `3306410`). Task 11 later adds the `nativeMessaging` permission and drops the API host permission.

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

**Result (done, commit `9696525`):** see `docs/spike-notes.md`. `format` + adaptive thinking works, Opus rejects `between_tools`, this key needs `anthropic-workspace-id`, and the organization rejects browser-origin requests even with the browser-access header. That last finding is why the API path is the native host (Tasks 10 and 11). The committed script also sends `anthropic-workspace-id` from `ANTHROPIC_WORKSPACE_ID`.

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

The question to answer: when Enter is pressed mid-composition, does Chrome fire one keydown (`isComposing=true`), or that plus a second keydown with `isComposing=false`? Task 20's handler covers both cases. Record which one happens.

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

The `javascript_tool` runs in the page's main world; the extension's content script runs in an isolated world. Both share the DOM, and `execCommand` produces real input events, so a pass here carries over. Task 19's live check confirms it from the isolated world.

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

Task 15 asserts these values.

**Step 6: Fill in `selectors.js` placeholders in this plan**

Edit Task 15 in this plan file, replacing the `__FILL__` markers with the strings found here.

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

test('sentKey ignores whitespace differences', async () => {
  assert.equal(await sentKey('t1', ' see  you\n'), await sentKey('t1', 'see you'));
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

// Whitespace-normalized: composer text at send time and bubble text read later must hash the same.
export async function sentKey(threadId, text) {
  return 's:' + (await sha256hex(JSON.stringify([threadId, text.replace(/\s+/g, ' ').trim()])));
}

export function expiredKeys(all, now) {
  return Object.entries(all)
    .filter(([k, v]) => (k.startsWith('c:') || k.startsWith('s:')) && typeof v?.ts === 'number' && now - v.ts > PRUNE_MS)
    .map(([k]) => k);
}
```

**Step 4: Run, expect PASS**

Run: `node --test tests/keys.test.js`
Expected: 7 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/keys.js tests/keys.test.js
git commit -m "feat: storage keys, hashing, defaults, pruning"
```

---

### Task 6: `api.js`

The client does not know how a request travels. It takes a `transport(body)` that resolves to `{status, retry_after, body}`. In the extension, the transport is the native host (Task 11). In Node scripts, it is a small `fetch` wrapper (Task 22).

`status: 0` is the host's code for a local failure. `body.error.type` says which:
- `host_config` (key or workspace file unreadable): kind `auth`
- `host_network` (DNS, connection, timeout): kind `network`
- anything else: kind `host`

**Files:**
- Create: `src/lib/api.js`
- Test: `tests/api.test.js`

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { callClaude, callJson, ApiError } from '../src/lib/api.js';

const noSleep = async () => {};
function fakeTransport(responses) {
  const calls = [];
  const fn = async (body) => {
    calls.push(body);
    const r = responses.shift();
    if (r instanceof Error) throw r;
    return { status: r.status, retry_after: r.retry_after ?? null, body: r.body ?? {} };
  };
  fn.calls = calls;
  return fn;
}

test('passes the body through unchanged and returns the response body', async () => {
  const t = fakeTransport([{ status: 200, body: { content: [] } }]);
  const r = await callClaude({ model: 'm' }, { transport: t, sleep: noSleep });
  assert.deepEqual(t.calls[0], { model: 'm' });
  assert.deepEqual(r, { content: [] });
});

test('retries 529 twice then fails as overloaded', async () => {
  const t = fakeTransport([{ status: 529 }, { status: 529 }, { status: 529 }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'overloaded');
  assert.equal(t.calls.length, 3);
});

test('429 honours retry_after then succeeds', async () => {
  const waits = [];
  const t = fakeTransport([{ status: 429, retry_after: '3' }, { status: 200, body: { ok: 1 } }]);
  const r = await callClaude({}, { transport: t, sleep: async (ms) => waits.push(ms) });
  assert.deepEqual(r, { ok: 1 });
  assert.deepEqual(waits, [3000]);
});

test('spend-limit 429 does not retry', async () => {
  const t = fakeTransport([{ status: 429, body: { error: { message: 'cap', details: { error_code: 'enforced_spend_limit_reached' } } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'spend_limit');
  assert.equal(t.calls.length, 1);
});

test('401 is auth, no retry', async () => {
  const t = fakeTransport([{ status: 401, body: { error: { message: 'bad key' } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'auth' && e.message === 'bad key');
  assert.equal(t.calls.length, 1);
});

test('status 0 host_config is auth, no retry', async () => {
  const t = fakeTransport([{ status: 0, body: { error: { type: 'host_config', message: 'cannot read API key config' } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'auth' && /API key/.test(e.message));
  assert.equal(t.calls.length, 1);
});

test('status 0 host_network retries then fails as network', async () => {
  const net = { status: 0, body: { error: { type: 'host_network', message: 'down' } } };
  const t = fakeTransport([net, { ...net }, { ...net }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'network');
  assert.equal(t.calls.length, 3);
});

test('transport rejection retries then fails as host', async () => {
  const t = fakeTransport([new ApiError('host', 'gone'), new ApiError('host', 'gone'), new ApiError('host', 'gone')]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'host' && e.message === 'gone');
  assert.equal(t.calls.length, 3);
});

test('callJson re-requests once on parse error', async () => {
  const t = fakeTransport([{ status: 200, body: { n: 1 } }, { status: 200, body: { n: 2 } }]);
  let seen = 0;
  const parse = (resp) => { seen++; if (resp.n === 1) throw new ApiError('parse', 'bad'); return resp.n; };
  assert.equal(await callJson({}, parse, { transport: t, sleep: noSleep }), 2);
  assert.equal(seen, 2);
});

test('callJson gives up after second parse error', async () => {
  const t = fakeTransport([{ status: 200 }, { status: 200 }]);
  const parse = () => { throw new ApiError('parse', 'bad'); };
  await assert.rejects(callJson({}, parse, { transport: t, sleep: noSleep }), (e) => e.kind === 'parse');
  assert.equal(t.calls.length, 2);
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/api.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/api.js`**

```js
// kind: auth | host | spend_limit | rate | overloaded | server | bad_request | network | refused | parse
export class ApiError extends Error {
  constructor(kind, message, status) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

const RETRYABLE = new Set(['rate', 'overloaded', 'server', 'network', 'host']);
const backoff = (attempt) => 1000 * 2 ** attempt;
const realSleep = (ms) => new Promise((r) => setTimeout(r, ms));

function classify(status, body) {
  if (status === 0) {
    const t = body?.error?.type;
    if (t === 'host_config') return 'auth';
    if (t === 'host_network') return 'network';
    return 'host';
  }
  if (status === 401 || status === 403) return 'auth';
  if (status === 429) {
    return body?.error?.details?.error_code === 'enforced_spend_limit_reached' ? 'spend_limit' : 'rate';
  }
  if (status === 529) return 'overloaded';
  if (status >= 500) return 'server';
  return 'bad_request';
}

// transport(body) resolves to { status, retry_after, body } or rejects (ApiError 'host' on port failure).
export async function callClaude(body, { transport, sleep = realSleep, retries = 2 } = {}) {
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await transport(body);
    } catch (e) {
      const err = e instanceof ApiError ? e : new ApiError('host', String(e?.message || e));
      if (RETRYABLE.has(err.kind) && attempt < retries) { await sleep(backoff(attempt)); continue; }
      throw err;
    }
    if (res.status >= 200 && res.status < 300) return res.body;
    const kind = classify(res.status, res.body);
    if (RETRYABLE.has(kind) && attempt < retries) {
      const ra = Number(res.retry_after);
      await sleep(ra > 0 ? ra * 1000 : backoff(attempt));
      continue;
    }
    throw new ApiError(kind, res.body?.error?.message || `HTTP ${res.status}`, res.status);
  }
}

// parse(resp) returns the value or throws ApiError('parse'). One re-request on parse failure.
export async function callJson(body, parse, opts) {
  try {
    return parse(await callClaude(body, opts));
  } catch (e) {
    if (e.kind !== 'parse') throw e;
    return parse(await callClaude(body, opts));
  }
}
```

`Number(null)` is `0` and `Number(undefined)` is `NaN`, so a missing `retry_after` falls back to exponential backoff.

**Step 4: Run, expect PASS**

Run: `node --test tests/api.test.js`
Expected: 10 tests PASS.

**Step 5: Commit**

```bash
git add src/lib/api.js tests/api.test.js
git commit -m "feat: transport-agnostic API client with retry, backoff, error kinds"
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

// useFormat: the Task 2 spike confirmed format works with adaptive thinking; false is only a fallback switch.
export const PROFILES = {
  incoming: { thinkingOff: true, effort: 'low', max_tokens: 8192, useFormat: true },
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

**Step 5: Task 2 decision gate**

The spike showed `format` works with adaptive thinking, so `useFormat` stays `true` on every profile. Nothing to change.

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
- `{ type: 'show', translation, back_translation, profile, lang, model }`: write the translation into the composer
- `{ type: 'restore', korean }`: write the Korean back into the composer and hide the note
- `{ type: 'sent', korean }`: let Enter through and record the sent message
- `{ type: 'fail', message, korean }`: put the Korean back if the composer holds something else, then show the error
- `{ type: 'none' }`

`lang: null` in a translate effect means "resolve from the thread".

Rules beyond the obvious:
- Enter in `preview` with Hangul in the composer means the user wrote a new Korean draft (cleared the box, or Instagram's Send button already sent the old preview). It starts a **new** translation of that text, never a send. The one exception is a Korean target (`lang === 'ko'`), where Hangul is the expected output.
- `fail` and Esc while `translating` both carry the Korean original back, so a failed or cancelled re-translate from preview never leaves a stale translation in the composer.

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

// idle -> translating -> preview for `korean`, returns the preview state
function toPreview(korean, { hard = false, lang = 'en' } = {}) {
  const a = reduce(initial(), { type: 'enter', text: korean, hard });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'T', back_translation: korean, lang, model: 'claude-sonnet-5-5' });
  return b.state;
}

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

test('result shows preview with model; Enter sends with Korean original', () => {
  const a = reduce(initial(), { type: 'enter', text: '내일 봐', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'see u tmrw', back_translation: '내일 봐', lang: 'en', model: 'claude-sonnet-5-5' });
  assert.equal(b.state.mode, 'preview');
  assert.deepEqual(b.effect, { type: 'show', translation: 'see u tmrw', back_translation: '내일 봐', profile: 'outgoing', lang: 'en', model: 'claude-sonnet-5-5' });
  const c = reduce(b.state, { type: 'enter', text: 'see u tmrw!', hard: false });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'sent', korean: '내일 봐' });
});

test('stale result is ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId + 99, translation: 'x', back_translation: 'y', lang: 'en', model: 'm' });
  assert.equal(b.state.mode, 'translating');
  assert.deepEqual(b.effect, { type: 'none' });
});

test('Alt+Enter outside preview uses hard profile', () => {
  const { effects } = run([{ type: 'enter', text: '가자', hard: true }]);
  assert.equal(effects[0].profile, 'hard');
});

test('Alt+Enter inside preview re-translates stored Korean with hard', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: "let's go (edited)", hard: true });
  assert.equal(c.state.mode, 'translating');
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.korean, '가자');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'en');
});

test('Hangul Enter in preview starts a new translation of the new text', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: '밥 먹자', hard: false });
  assert.equal(c.state.mode, 'translating');
  assert.equal(c.state.korean, '밥 먹자');
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.korean, '밥 먹자');
  assert.equal(c.effect.profile, 'outgoing');
  assert.equal(c.effect.lang, null);
});

test('Hangul Enter in preview with a Korean target sends', () => {
  const p = toPreview('가자', { lang: 'ko' });
  const c = reduce(p, { type: 'enter', text: '가자고', hard: false });
  assert.deepEqual(c.effect, { type: 'sent', korean: '가자' });
});

test('language change in preview re-translates with same profile', () => {
  const p = toPreview('가자', { hard: true });
  const c = reduce(p, { type: 'lang', lang: 'ru' });
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'ru');
  assert.equal(c.effect.korean, '가자');
});

test('Esc in preview restores Korean', () => {
  const c = reduce(toPreview('가자'), { type: 'esc' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'restore', korean: '가자' });
});

test('Esc while translating restores Korean; late result ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'esc' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'restore', korean: '가자' });
  const c = reduce(b.state, { type: 'result', reqId: a.effect.reqId, translation: 'go', back_translation: '가자', lang: 'en', model: 'm' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'none' });
});

test('failure returns to idle and carries the Korean', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'fail', reqId: a.effect.reqId, message: 'overloaded' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'fail', message: 'overloaded', korean: '가자' });
});

test('failed re-translate from preview still carries the Korean', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: 'T', hard: true });
  const d = reduce(c.state, { type: 'fail', reqId: c.effect.reqId, message: 'host' });
  assert.deepEqual(d.effect, { type: 'fail', message: 'host', korean: '가자' });
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
        if (hasHangul(e.text) && s.lang !== 'ko') return translate(s, e.text, profile, null); // new draft
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
        effect: {
          type: 'show', translation: e.translation, back_translation: e.back_translation,
          profile: s.profile, lang: e.lang, model: e.model,
        },
      };
    case 'fail':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return { state: idle(s), effect: { type: 'fail', message: e.message, korean: s.korean } };
    case 'lang':
      if (s.mode !== 'preview') return { state: s, effect: { type: 'none' } };
      return translate(s, s.korean, s.profile, e.lang);
    case 'esc':
      if (s.mode === 'preview' || s.mode === 'translating') {
        return { state: idle(s), effect: { type: 'restore', korean: s.korean } };
      }
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
Expected: 14 tests PASS.

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

# Sprint 3: Native host, background and options

### Task 10: Native messaging host (Python, TDD)

The host is a stdlib-only Python 3 script. Chrome starts it when the background calls `connectNative`, and stops it when the port closes. There is no daemon, no port and no systemd unit.

Protocol on stdin/stdout (UTF-8 JSON, each message preceded by a 4-byte length in native byte order):
- request: `{id, body}`, where `body` is the Messages API request body
- reply: `{id, status, retry_after, body}`
  - `status` is the HTTP status
  - `status: 0` means a local failure, with `body.error.type` set to `host_config` (key/workspace file unreadable), `host_network` (DNS, connection, timeout) or `host_error` (anything else)

Rules:
- The key and the workspace ID are read from disk on every request, so a rotated key is picked up without restarting anything.
- The key is never logged or written to stdout or stderr. Error messages name the file and the exception type only.
- Each request runs in its own thread. Writes to stdout are serialized with a lock, so replies never interleave.
- A reply larger than 1 MB (Chrome's limit) becomes a `host_error` reply.

**Files:**
- Create: `host/ig_translate_host.py`, `host/test_host.py`

**Step 1: Write the failing test `host/test_host.py`**

```python
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

# Run as `python3 -I host/test_host.py`. Isolated mode does not add the script dir to sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ig_translate_host as h  # noqa: E402


def make_home(key='sk-ant-test-123', ws='wrkspc_test'):
    d = tempfile.mkdtemp()
    base = os.path.join(d, '.config', 'anthropic')
    os.makedirs(os.path.join(base, 'configs'))
    if key is not None:
        with open(os.path.join(base, 'api-key'), 'w') as f:
            f.write(key + '\n')
    with open(os.path.join(base, 'configs', 'default.json'), 'w') as f:
        json.dump({'workspace_id': ws}, f)
    return d


class FakeResp:
    def __init__(self, status, body, headers=None):
        self.status = status
        self._b = json.dumps(body).encode()
        self.headers = headers or {}

    def read(self):
        return self._b

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Framing(unittest.TestCase):
    def test_round_trip(self):
        msg = {'id': 7, 'body': {'text': '안녕 привет'}}
        buf = io.BytesIO(h.encode_message(msg))
        self.assertEqual(h.read_message(buf), msg)
        self.assertIsNone(h.read_message(buf))

    def test_length_is_utf8_byte_count(self):
        data = h.encode_message({'t': '안'})
        (n,) = struct.unpack('=I', data[:4])
        self.assertEqual(n, len(data) - 4)

    def test_write_message(self):
        out = io.BytesIO()
        h.write_message(out, {'id': 1})
        out.seek(0)
        self.assertEqual(h.read_message(out), {'id': 1})

    def test_oversized_reply_becomes_host_error(self):
        out = io.BytesIO()
        h.write_message(out, {'id': 9, 'status': 200, 'body': {'x': 'a' * (h.MAX_REPLY + 1)}})
        out.seek(0)
        r = h.read_message(out)
        self.assertEqual(r['id'], 9)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_error')


class Headers(unittest.TestCase):
    def test_reads_key_and_workspace(self):
        hd = h.build_headers(make_home())
        self.assertEqual(hd['x-api-key'], 'sk-ant-test-123')
        self.assertEqual(hd['anthropic-workspace-id'], 'wrkspc_test')
        self.assertEqual(hd['anthropic-version'], '2023-06-01')
        self.assertEqual(hd['content-type'], 'application/json')
        names = {k.lower() for k in hd}
        self.assertNotIn('origin', names)
        self.assertNotIn('anthropic-dangerous-direct-browser-access', names)

    def test_workspace_optional(self):
        hd = h.build_headers(make_home(ws=None))
        self.assertNotIn('anthropic-workspace-id', hd)


class Handle(unittest.TestCase):
    def test_missing_key_file(self):
        op = mock.Mock()
        r = h.handle({'id': 3, 'body': {}}, make_home(key=None), urlopen=op)
        self.assertEqual(r['id'], 3)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_config')
        op.assert_not_called()

    def test_success(self):
        op = mock.Mock(return_value=FakeResp(200, {'content': []}))
        r = h.handle({'id': 1, 'body': {'model': 'm'}}, make_home(), urlopen=op)
        self.assertEqual(r, {'id': 1, 'status': 200, 'retry_after': None, 'body': {'content': []}})
        req = op.call_args[0][0]
        self.assertEqual(req.full_url, h.API_URL)
        self.assertEqual(req.get_method(), 'POST')
        self.assertEqual(json.loads(req.data), {'model': 'm'})
        self.assertEqual(req.get_header('X-api-key'), 'sk-ant-test-123')
        self.assertEqual(op.call_args[1]['timeout'], 120)

    def test_http_error_keeps_status_retry_after_and_body(self):
        err = urllib.error.HTTPError(h.API_URL, 429, 'rate', {'retry-after': '3'},
                                     io.BytesIO(b'{"error":{"message":"slow"}}'))
        r = h.handle({'id': 2, 'body': {}}, make_home(), urlopen=mock.Mock(side_effect=err))
        self.assertEqual(r['status'], 429)
        self.assertEqual(r['retry_after'], '3')
        self.assertEqual(r['body']['error']['message'], 'slow')

    def test_network_error(self):
        op = mock.Mock(side_effect=urllib.error.URLError('down'))
        r = h.handle({'id': 4, 'body': {}}, make_home(), urlopen=op)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_network')

    def test_errors_never_contain_the_key(self):
        op = mock.Mock(side_effect=urllib.error.URLError('down'))
        for home in (make_home(key=None), make_home()):
            r = h.handle({'id': 5, 'body': {}}, home, urlopen=op)
            self.assertNotIn('sk-ant-test-123', json.dumps(r))

    def test_safe_handle_catches_bad_request(self):
        r = h.safe_handle({'id': 6}, make_home())
        self.assertEqual(r['id'], 6)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_error')


if __name__ == '__main__':
    unittest.main()
```

**Step 2: Run, expect FAIL**

Run: `python3 -I host/test_host.py`
Expected: `ModuleNotFoundError: No module named 'ig_translate_host'`.

**Step 3: Implement `host/ig_translate_host.py`**

```python
#!/usr/bin/python3
"""ig-translate native messaging host.

Chrome sends {id, body} messages on stdin. Each body is sent to the Anthropic Messages API
and the reply {id, status, retry_after, body} is written to stdout. Messages in both
directions are UTF-8 JSON preceded by a 32-bit length in native byte order.
The API key never leaves this process; nothing here logs it.
"""
import json
import os
import struct
import sys
import threading
import urllib.error
import urllib.request

API_URL = 'https://api.anthropic.com/v1/messages'
TIMEOUT_S = 120
MAX_REPLY = 1024 * 1024  # Chrome rejects host messages larger than 1 MB

_out_lock = threading.Lock()


def read_message(stream):
    raw = stream.read(4)
    if len(raw) < 4:
        return None
    (n,) = struct.unpack('=I', raw)
    data = stream.read(n)
    if len(data) < n:
        return None
    return json.loads(data.decode('utf-8'))


def encode_message(obj):
    data = json.dumps(obj, ensure_ascii=False).encode('utf-8')
    return struct.pack('=I', len(data)) + data


def local_error(req_id, kind, message):
    return {'id': req_id, 'status': 0, 'retry_after': None,
            'body': {'error': {'type': kind, 'message': message}}}


def write_message(stream, obj):
    data = encode_message(obj)
    if len(data) - 4 > MAX_REPLY:
        data = encode_message(local_error(obj.get('id'), 'host_error', 'reply larger than 1 MB'))
    with _out_lock:
        stream.write(data)
        stream.flush()


def build_headers(home):
    base = os.path.join(home, '.config', 'anthropic')
    with open(os.path.join(base, 'api-key')) as f:
        key = f.read().strip()
    with open(os.path.join(base, 'configs', 'default.json')) as f:
        workspace = json.load(f).get('workspace_id')
    headers = {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
    }
    if workspace:
        headers['anthropic-workspace-id'] = workspace
    return headers


def handle(req, home, urlopen=urllib.request.urlopen):
    req_id = req.get('id')
    try:
        headers = build_headers(home)
    except (OSError, ValueError) as e:
        where = getattr(e, 'filename', None) or '~/.config/anthropic'
        return local_error(req_id, 'host_config', f'cannot read API key config ({type(e).__name__}: {where})')
    request = urllib.request.Request(API_URL, data=json.dumps(req['body']).encode('utf-8'),
                                     headers=headers, method='POST')
    try:
        with urlopen(request, timeout=TIMEOUT_S) as resp:
            return {'id': req_id, 'status': resp.status,
                    'retry_after': resp.headers.get('retry-after'), 'body': json.loads(resp.read())}
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except ValueError:
            body = {}
        return {'id': req_id, 'status': e.code, 'retry_after': e.headers.get('retry-after'), 'body': body}
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        reason = getattr(e, 'reason', None) or type(e).__name__
        return local_error(req_id, 'host_network', f'network: {reason}')


def safe_handle(req, home):
    try:
        return handle(req, home)
    except Exception as e:  # never let one bad request kill the host
        return local_error(req.get('id') if isinstance(req, dict) else None, 'host_error', type(e).__name__)


def main():
    home = os.path.expanduser('~')
    stdin, stdout = sys.stdin.buffer, sys.stdout.buffer
    while True:
        try:
            req = read_message(stdin)
        except ValueError:
            continue  # unparseable JSON has no id to reply to; the frame was consumed, keep reading
        if req is None:
            break  # Chrome closed the port
        threading.Thread(target=lambda r=req: write_message(stdout, safe_handle(r, home)), daemon=True).start()


if __name__ == '__main__':
    main()
```

Hand-checked against the tests:
- `HTTPError(url, code, msg, hdrs, fp)` with a dict `hdrs`: `e.headers` is that dict, so `.get('retry-after')` works.
- `urllib.request.Request.get_header` looks names up as `str.capitalize()`, so `x-api-key` is stored as `X-api-key`.
- `safe_handle({'id': 6})` raises `KeyError('body')` inside `handle`, which becomes a `host_error`.
- `URLError('down').reason` is `'down'`.

**Step 4: Run, expect PASS**

Run: `python3 -I host/test_host.py`
Expected: `Ran 12 tests`, `OK`.

**Step 5: Write `host/install.sh`**

```bash
#!/usr/bin/env bash
# Usage: host/install.sh <extension-id>
# Registers the ig-translate native messaging host for the current user's Google Chrome.
set -euo pipefail
id="${1:?usage: host/install.sh <extension-id>}"
[[ "$id" =~ ^[a-p]{32}$ ]] || { echo "not a Chrome extension id: $id" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
host="$here/ig_translate_host.py"
dir="$HOME/.config/google-chrome/NativeMessagingHosts"
mkdir -p "$dir"
chmod +x "$host"
cat > "$dir/com.northprot.ig_translate.json" <<EOF
{
  "name": "com.northprot.ig_translate",
  "description": "ig-translate Claude API bridge",
  "path": "$host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$id/"]
}
EOF
echo "installed $dir/com.northprot.ig_translate.json"
```

Run: `chmod +x host/install.sh && bash -n host/install.sh`
Expected: no output (syntax OK). The real install happens in Task 14, once the extension ID is known.

**Step 6: Commit**

```bash
git add host/
git commit -m "feat: native messaging host for Claude API calls"
```

---

### Task 11: Native transport in the extension

**Files:**
- Create: `src/lib/native.js`
- Test: `tests/native.test.js`
- Modify: `manifest.json`

There is one long-lived port. Requests carry an increasing `id`, and replies resolve the matching pending promise. When the port disconnects, every pending request on that port is rejected with `ApiError('host', <chrome.runtime.lastError message>)`, and the next request opens a new port. A reply that never comes is rejected after 150 s, above the host's 120 s urllib timeout.

**Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createNativeTransport } from '../src/lib/native.js';

function fakePort() {
  const msgL = [];
  const discL = [];
  return {
    sent: [],
    postMessage(m) { this.sent.push(m); },
    onMessage: { addListener: (f) => msgL.push(f) },
    onDisconnect: { addListener: (f) => discL.push(f) },
    reply(m) { msgL.forEach((f) => f(m)); },
    disconnect() { discL.forEach((f) => f()); },
  };
}

function setup(lastError, timeoutMs) {
  const ports = [];
  const t = createNativeTransport(() => { const p = fakePort(); ports.push(p); return p; }, lastError, timeoutMs);
  return { t, ports };
}

test('one port, replies matched by id', async () => {
  const { t, ports } = setup();
  const a = t({ n: 1 });
  const b = t({ n: 2 });
  assert.equal(ports.length, 1);
  const [ma, mb] = ports[0].sent;
  assert.deepEqual(ma.body, { n: 1 });
  assert.notEqual(ma.id, mb.id);
  ports[0].reply({ id: mb.id, status: 200, retry_after: null, body: { n: 2 } });
  ports[0].reply({ id: ma.id, status: 429, retry_after: '3', body: {} });
  assert.deepEqual(await b, { status: 200, retry_after: null, body: { n: 2 } });
  assert.deepEqual(await a, { status: 429, retry_after: '3', body: {} });
});

test('unknown reply ids are ignored', async () => {
  const { t, ports } = setup();
  const a = t({});
  ports[0].reply({ id: 999, status: 200, body: {} });
  ports[0].reply({ id: ports[0].sent[0].id, status: 200, retry_after: null, body: { ok: 1 } });
  assert.deepEqual((await a).body, { ok: 1 });
});

test('disconnect rejects pending with host kind; next call reconnects', async () => {
  const { t, ports } = setup(() => 'Specified native messaging host not found.');
  const a = t({});
  ports[0].disconnect();
  await assert.rejects(a, (e) => e.kind === 'host' && /not found/.test(e.message));
  const b = t({});
  assert.equal(ports.length, 2);
  ports[1].reply({ id: ports[1].sent[0].id, status: 200, retry_after: null, body: {} });
  assert.equal((await b).status, 200);
});

test('connect throwing rejects with host kind', async () => {
  const t = createNativeTransport(() => { throw new Error('nativeMessaging permission missing'); });
  await assert.rejects(t({}), (e) => e.kind === 'host' && /permission/.test(e.message));
});

test('no reply rejects after the timeout', async () => {
  const { t } = setup(undefined, 20);
  await assert.rejects(t({}), (e) => e.kind === 'host' && /timed out/.test(e.message));
});
```

**Step 2: Run, expect FAIL**

Run: `node --test tests/native.test.js`
Expected: FAIL, module not found.

**Step 3: Implement `src/lib/native.js`**

```js
import { ApiError } from './api.js';

export const HOST_NAME = 'com.northprot.ig_translate';

// connect() returns a Port-like object: { postMessage, onMessage.addListener, onDisconnect.addListener }.
// lastError() returns why a port closed (chrome.runtime.lastError?.message), read inside onDisconnect.
export function createNativeTransport(connect, lastError = () => undefined, timeoutMs = 150000) {
  let conn = null; // { port, pending: Map<id, {resolve, reject, timer}> }
  let nextId = 1;

  function open() {
    const port = connect();
    const c = { port, pending: new Map() };
    port.onMessage.addListener((msg) => {
      const p = c.pending.get(msg?.id);
      if (!p) return;
      c.pending.delete(msg.id);
      clearTimeout(p.timer);
      p.resolve({ status: msg.status, retry_after: msg.retry_after ?? null, body: msg.body });
    });
    port.onDisconnect.addListener(() => {
      const reason = lastError() || 'native host disconnected';
      if (conn === c) conn = null;
      for (const p of c.pending.values()) { clearTimeout(p.timer); p.reject(new ApiError('host', reason)); }
      c.pending.clear();
    });
    return c;
  }

  return function transport(body) {
    return new Promise((resolve, reject) => {
      let c;
      try {
        c = conn || (conn = open());
      } catch (e) {
        reject(new ApiError('host', String(e?.message || e)));
        return;
      }
      const id = nextId++;
      const timer = setTimeout(() => {
        if (c.pending.delete(id)) reject(new ApiError('host', 'native host timed out'));
      }, timeoutMs);
      c.pending.set(id, { resolve, reject, timer });
      try {
        c.port.postMessage({ id, body });
      } catch (e) {
        c.pending.delete(id);
        clearTimeout(timer);
        if (conn === c) conn = null;
        reject(new ApiError('host', String(e?.message || e)));
      }
    });
  };
}
```

Hand-checked: in "connect throwing", `open()` throws before `conn` is assigned, so the next call tries again. In the timeout test, `setup(undefined, 20)` passes `lastError` as `undefined`, so the default parameter applies.

**Step 4: Run, expect PASS**

Run: `node --test tests/native.test.js`
Expected: 5 tests PASS.

**Step 5: Update `manifest.json`**

Add the `nativeMessaging` permission and drop the API host permission, since the browser no longer talks to the API:

```json
  "permissions": ["storage", "nativeMessaging"],
  "host_permissions": [
    "https://www.instagram.com/*"
  ],
```

Append to `tests/smoke.test.js`:

```js
test('manifest uses native messaging, not direct API access', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.ok(m.permissions.includes('nativeMessaging'));
  assert.equal(m.host_permissions.some((h) => h.includes('anthropic')), false);
});
```

Run: `npm test`
Expected: all PASS.

**Step 6: Commit**

```bash
git add src/lib/native.js tests/native.test.js manifest.json tests/smoke.test.js
git commit -m "feat: native messaging transport, manifest permission"
```

---

### Task 12: `background.js`

The background service worker is not unit-tested directly; it is glue over the tested libraries. Keep logic out of it. Message types and replies:

| `type` | request | reply `data` |
|---|---|---|
| `getThread` | `{threadId}` | thread object with defaults |
| `setThread` | `{threadId, patch}` | updated thread |
| `incoming` | `{threadId, context, items:[{id, text, from}], updateLang}` | `{ [id]: {src_lang, translation} \| null }` (null = leave as is) |
| `outgoing` | `{threadId, context, korean, profile, lang}` | `{translation, back_translation, lang, model}` |
| `sent` | `{threadId, text, korean}` | `true` |
| `lookupSent` | `{threadId, texts}` | `{ [text]: korean }` |
| `suggestMemo` | `{threadId, context}` | `memo` string |
| `badge` | `{text}` | `true` |

Every reply is `{ok: true, data}` or `{ok: false, error: {kind, message}}`.

`updateLang` is `true` only for the initial scan of a thread and for freshly arrived messages. Back-filled history and retries never move `partnerLang`, because "auto" means the language of the partner's **most recent** messages.

**Files:**
- Create: `src/background.js`

**Step 1: Write `src/background.js`**

```js
import { callJson, ApiError } from './lib/api.js';
import { createNativeTransport, HOST_NAME } from './lib/native.js';
import {
  buildIncomingRequest, buildOutgoingRequest, buildMemoRequest,
  parseIncoming, parseOutgoing, parseMemo,
} from './lib/prompts.js';
import { incomingTarget, resolveOutputLang, latestPartnerLang } from './lib/lang.js';
import { DEFAULT_SETTINGS, withThreadDefaults, threadKey, cacheKey, sentKey, expiredKeys } from './lib/keys.js';

const store = chrome.storage.local;
const BATCH = 20;
const transport = createNativeTransport(
  () => chrome.runtime.connectNative(HOST_NAME),
  () => chrome.runtime.lastError?.message,
);
const api = (body, parse) => callJson(body, parse, { transport });

async function getSettings() {
  const { settings } = await store.get('settings');
  return {
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
  await store.set({ [k]: { ...(got[k] || {}), ...patch } });
  return getThread(threadId);
}

async function incoming({ threadId, context, items, updateLang }) {
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
    const res = await api(body, parseIncoming);
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

  if (updateLang) {
    const ordered = items.filter((it) => out[it.id]).map((it) => ({ from: it.from, src_lang: out[it.id].src_lang }));
    const lang = latestPartnerLang(ordered);
    if (lang && lang !== thread.partnerLang) await setThread(threadId, { partnerLang: lang });
  }

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
  const r = await api(body, parseOutgoing);
  return { ...r, lang: target, model };
}

async function suggestMemo({ context }) {
  const settings = await getSettings();
  return api(buildMemoRequest({ model: settings.models.outgoing, context }), parseMemo);
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
- `BATCH = 20` with incoming `max_tokens: 8192` leaves room for long messages. A `max_tokens` stop is a parse error, and an identical re-request would only truncate again.
- `sentKey` normalizes whitespace (Task 5), so the composer text at send time and the bubble text read later hash the same.
- The port opens on the first API call and stays open, which also keeps the service worker alive during long calls. If Chrome stops the idle service worker, the port closes with it, and the next call reconnects.

**Step 2: Syntax check**

Run: `node --check src/background.js && npm test`
Expected: no syntax error; all tests PASS.

**Step 3: Commit**

```bash
git add src/background.js
git commit -m "feat: background router, cache, thread state, API calls via native host"
```

---

### Task 13: Options page

There is no API key field. The key lives only in `~/.config/anthropic/api-key`, which the native host reads.

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
  select { width: 100%; padding: 6px; box-sizing: border-box; }
  #saved { color: green; margin-left: 8px; }
  p.note { color: #666; }
</style>
<h1>ig-translate</h1>
<p class="note">API key: read by the native host from <code>~/.config/anthropic/api-key</code>. Install the host with <code>host/install.sh &lt;extension id&gt;</code>.</p>
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
<p><button id="save" type="button">Save</button><span id="saved"></span></p>
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
const models = { ...DEFAULT_SETTINGS.models, ...settings.models };
const threadDefaults = { ...DEFAULT_SETTINGS.threadDefaults, ...settings.threadDefaults };
for (const id of ['incoming', 'outgoing', 'hard']) $(id).value = models[id];
for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).value = threadDefaults[id];

$('save').onclick = async () => {
  await chrome.storage.local.set({
    settings: {
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

### Task 14: Load unpacked, install the host, smoke-test end to end (manual)

**Step 1:** Create a stub `src/content/loader.js` containing only `// filled in Task 16`, and an empty `src/content/style.css`, so the manifest loads.

**Step 2:** Ask the user to open `chrome://extensions`, enable Developer mode, click "Load unpacked", pick `/home/cyan/projects/ig-translate`, and paste the extension ID shown on the card. An unpacked extension's ID is derived from its path, so it stays the same as long as the folder does not move.

**Step 3: Install the host**

Run: `host/install.sh <extension-id>`
Expected: `installed /home/cyan/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json`.

Then `python3 -I host/test_host.py` once more (Expected: OK). Chrome reads the host manifest on each `connectNative`, so no browser restart is needed.

**Step 4: End-to-end call**

Ask the user to right-click the options page, choose Inspect, and run this in its console. Service workers forbid `import()`, so the options page is the console to use. Messages from it go through the background exactly as the content script's will.

```js
console.time('outgoing');
console.log(await chrome.runtime.sendMessage({ type: 'outgoing', threadId: 'smoke', context: [], korean: '내일 보자', profile: 'outgoing', lang: 'en' }));
console.timeEnd('outgoing');
```

Expected: `{ok: true, data: {translation, back_translation, lang: 'en', model: 'claude-sonnet-5-5'}}`.

If `ok: false` with kind `host`, the message names the cause:
- "Specified native messaging host not found": re-run Step 3
- "Access to the specified native messaging host is forbidden": the extension ID is wrong
- "Native host has exited": run `python3 -I host/test_host.py`, and check the host's shebang and executable bit

**Step 5: Long `hard` call (the 30 s question)**

In the same console:

```js
const long = '어제 진짜 웃긴 일 있었어. 지하철에서 졸다가 내릴 역 지나쳐서 종점까지 갔는데, 거기서 고등학교 동창을 만났어. 걔도 똑같이 졸다가 지나친 거래. 그래서 둘이 그냥 근처 국밥집 가서 밥 먹고 옛날 얘기 엄청 했어. 담임 선생님 얘기, 수학여행 때 길 잃어버린 얘기, 축제 때 망한 공연 얘기까지. 다음 주에 다른 애들도 불러서 다시 모이기로 했는데, 너도 시간 되면 같이 가자. 장소는 아직 안 정했는데 아마 강남 쪽일 거야. 금요일 저녁 어때?';
console.time('hard');
console.log(await chrome.runtime.sendMessage({ type: 'outgoing', threadId: 'smoke', context: [], korean: long, profile: 'hard', lang: 'ru' }));
console.timeEnd('hard');
```

Expected: `ok: true`, even if it takes longer than 30 s. Record the time in `docs/spike-notes.md`. If it fails after about 30 s with a disconnect, the open-port keepalive is not holding, so stop and report BLOCKED.

**Step 6: Host-missing failure path**

Run: `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{,.off} && pkill -f '[i]g_translate_host.py' || true`

The bracket pattern keeps `pkill` from matching its own shell. Rerun the Step 4 snippet.
Expected: after about 3 s of retries, `{ok: false, error: {kind: 'host', message: 'Specified native messaging host not found.'}}`.

Restore the manifest: `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{.off,}`. Rerun Step 4 and expect `ok: true`, which shows the transport reconnects.

**Step 7: Confirm content-script dynamic import**

Temporarily replace the stub `src/content/loader.js` with:

```js
(async () => {
  const m = await import(chrome.runtime.getURL('src/lib/lang.js'));
  console.log('[igt] dynamic import ok', m.hasHangul('안녕'));
})();
```

Reload the extension, then open any `instagram.com` page. The page console should show `[igt] dynamic import ok true`. If it throws, stop and report BLOCKED. The fallback is listing every content file as classic scripts in `content_scripts.js`, which changes Tasks 15 to 20. Record the result in `docs/spike-notes.md`, then put the stub back.

**Step 8: Commit**

```bash
git add src/content/loader.js src/content/style.css docs/spike-notes.md
git commit -m "chore: loadable extension, native host smoke test recorded"
```

---

# Sprint 4: Incoming translation in the page

### Task 15: `selectors.js` and `dom.js` readers (snapshot tests)

**Files:**
- Create: `src/content/selectors.js`, `src/content/dom.js`
- Test: `tests/dom.test.js`

**Step 1: Write `src/content/selectors.js` with the Task 3 findings**

```js
// Every Instagram DOM assumption lives here. When Instagram changes, re-run the Task 3 spike and edit this file.
export const SEL = {
  threadRoot: '[role="main"]',                                     // holds the message scroller (and the inbox list, which has no articles)
  messageRow: '[role="article"][aria-roledescription="message"]',  // one message
  messageText: 'div[dir="auto"]',                                  // leaf text div inside a text bubble; media captions are span-only
  composer: 'div[role="textbox"][contenteditable="true"]',         // Lexical editor
  replyLabelPrefix: 'Reply to message from ',
  viewerAvatar: 'img[alt$="\'s profile picture"]',
};

const AVATAR_SUFFIX = "'s profile picture";

// Viewer username from the sidebar profile link (outside main). null if not found = selector miss.
export function findViewerName(doc) {
  for (const img of doc.querySelectorAll(`a[href] ${SEL.viewerAvatar}`)) {
    if (img.closest(SEL.threadRoot)) continue;
    const alt = img.getAttribute('alt');
    return alt.slice(0, -AVATAR_SUFFIX.length);
  }
  return null;
}

// 'me' | 'partner'. The reply button lives in the row group, a sibling of the article.
// Group chats: everyone except the viewer counts as partner, the safe direction.
export function senderOf(row, viewer) {
  const label = row.closest('[role="group"]')
    ?.querySelector(`[aria-label^="${SEL.replyLabelPrefix}"]`)
    ?.getAttribute('aria-label');
  const name = label ? label.slice(SEL.replyLabelPrefix.length) : null;
  return name === viewer ? 'me' : 'partner';
}
```

**Step 2: Write the failing test** (the expected numbers come from `docs/spike-notes.md`, Task 3 Step 5)

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { readMessages, findThreadRoot } from '../src/content/dom.js';
import { findViewerName } from '../src/content/selectors.js';

const html = readFileSync(new URL('./fixtures/thread.html', import.meta.url), 'utf8');
const doc = new JSDOM(`<body>${html}</body>`).window.document;

const EXPECTED_ROWS = 7; // text rows msg 13, 17, 21, 25, 29, 33, 37 (docs/spike-notes.md)
const EXPECTED_SENDERS = ['partner', 'partner', 'partner', 'partner', 'partner', 'me', 'me'];
const VIEWER = 'viewer_user'; // the snapshot holds only main, so the viewer is passed in

test('finds thread root', () => {
  assert.ok(findThreadRoot(doc));
});

test('reads text rows with sender, in order', () => {
  const msgs = readMessages(findThreadRoot(doc), VIEWER);
  assert.equal(msgs.length, EXPECTED_ROWS);
  assert.deepEqual(msgs.map((m) => m.from), EXPECTED_SENDERS);
  for (const m of msgs) assert.match(m.text, /^msg \d+/);
});

test('findViewerName reads the sidebar profile link, ignores avatars inside main', () => {
  const d = new JSDOM(`<body>
    <div role="main"><a href="/x/"><img alt="partner_user's profile picture"></a></div>
    <nav><a href="/viewer_user/"><img alt="viewer_user's profile picture"></a></nav>
  </body>`).window.document;
  assert.equal(findViewerName(d), 'viewer_user');
  assert.equal(findViewerName(new JSDOM('<body></body>').window.document), null);
});
```

**Step 3: Run, expect FAIL**

Run: `node --test tests/dom.test.js`
Expected: FAIL, module `dom.js` not found.

**Step 4: Implement the reader part of `src/content/dom.js`**

```js
import { SEL, senderOf, findViewerName } from './selectors.js';

export const findThreadRoot = (doc) => doc.querySelector(SEL.threadRoot);
export const findComposer = (doc) => doc.querySelector(SEL.composer);

// Text bubbles only, top to bottom. Rows without a text element (media, stickers) are skipped.
// viewer defaults to the live page's sidebar username; tests pass it explicitly.
export function readMessages(root, viewer = findViewerName(root.ownerDocument)) {
  const out = [];
  for (const row of root.querySelectorAll(SEL.messageRow)) {
    const textEl = row.querySelector(SEL.messageText);
    const text = textEl?.innerText ?? textEl?.textContent ?? '';
    if (!text.trim()) continue;
    out.push({ row, textEl, text: text.trim(), from: senderOf(row, viewer) });
  }
  return out;
}
```

jsdom has no layout, so `innerText` is undefined there and `textContent` is used. In Chrome `innerText` keeps line breaks.

Check that `SEL.messageText` cannot match the `.igt-tr` elements this extension inserts (Task 16), or translations would be read back as messages.

`senderOf` is structural (aria-label), so it runs in jsdom. Without a viewer name every row would count as partner, so Task 17 treats a missing viewer as a selector miss.

**Step 5: Run, expect PASS**

Run: `node --test tests/dom.test.js`
Expected: 3 tests PASS.

**Step 6: Commit**

```bash
git add src/content/selectors.js src/content/dom.js tests/dom.test.js
git commit -m "feat: Instagram selectors and message reader with snapshot test"
```

---

### Task 16: Rendering helpers and loader

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
    await start();
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

### Task 17: `main.js`, thread lifecycle and incoming

**Files:**
- Create: `src/content/main.js`

The thread object `current` carries three hook lists so later modules stay decoupled:
- `onTeardown`: cleanup when leaving the thread
- `onThreadUpdate(thread)`: the panel changed the thread settings
- `onMutate()`: the message list changed (debounced)

Thread switch safety:
- After an SPA switch from thread A to B, A's rows can still be in the DOM for a moment. `teardown` remembers A's rows. `waitForThread` waits until none of them remain **and** the row count is the same on two checks 300 ms apart.
- `initThread` re-checks the URL after its `await` and tears down anything set up meanwhile, so a fast A to B to C switch never leaves two sets of listeners.
- If Instagram reuses row nodes across threads, the stale-row wait never ends. After about 10 s it initialises anyway; Task 19 measures the switch time to catch this.

**Step 1: Write `src/content/main.js` (Task 18 adds the panel, Task 20 adds outgoing)**

```js
import { threadIdFromPath } from '../lib/keys.js';
import { isKoreanOnly } from '../lib/lang.js';
import { classifyAdded } from '../lib/classify.js';
import { findViewerName } from './selectors.js';
import { findThreadRoot, readMessages, renderTranslation, renderRetry, setHoverOriginal, clearTranslation } from './dom.js';

const CONTEXT_N = 30;
const DEBOUNCE_MS = 400;
const WAIT_MS = 300;
const WAIT_TRIES = 33; // about 10 s

export const ERROR_BANNERS = {
  auth: 'ig-translate: API key missing or rejected. Check ~/.config/anthropic/api-key.',
  host: 'ig-translate: native host not reachable. Run host/install.sh <extension id>, then reload the extension.',
};

export const ask = async (msg) => {
  const r = await chrome.runtime.sendMessage(msg);
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
};

export const initHooks = [];
let current = null; // { threadId, thread, root, observer, known, timer, onTeardown, onThreadUpdate, onMutate }
let staleRows = new WeakSet();
const bannersShown = new Set();

export async function start() {
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
  for (const m of readMessages(current.root)) staleRows.add(m.row);
  current.observer?.disconnect();
  clearTimeout(current.timer);
  current.onTeardown.forEach((f) => f());
  current = null;
}

function waitForThread(threadId, tries = 0, lastCount = -1) {
  if (threadIdFromPath(location.pathname) !== threadId) return; // navigated away meanwhile
  // No viewer name means senders cannot be told apart: treat it like a missing root (selector miss).
  const root = findViewerName(document) ? findThreadRoot(document) : null;
  const msgs = root ? readMessages(root) : [];
  const clean = !msgs.some((m) => staleRows.has(m.row));
  // Stable over two checks; an empty thread (new chat) must stay empty for about 1 s.
  if (root && clean && msgs.length === lastCount && (msgs.length > 0 || tries >= 3)) return initThread(threadId, root);
  if (tries >= WAIT_TRIES) {
    if (root) {
      if (!clean) console.warn('[igt] old thread rows still present after 10 s; initialising anyway');
      return initThread(threadId, root);
    }
    ask({ type: 'badge', text: '!' }).catch(() => {});
    console.warn('[igt] thread root not found; extension inactive on this page');
    return;
  }
  setTimeout(() => waitForThread(threadId, tries + 1, clean ? msgs.length : -1), WAIT_MS);
}

async function initThread(threadId, root) {
  const thread = await ask({ type: 'getThread', threadId });
  if (threadIdFromPath(location.pathname) !== threadId) return;
  teardown(); // anything a racing init set up meanwhile
  ask({ type: 'badge', text: '' }).catch(() => {});
  current = {
    threadId, thread, root, known: new WeakSet(), timer: null,
    onTeardown: [], onThreadUpdate: [], onMutate: [],
  };

  const msgs = readMessages(root);
  msgs.forEach((m) => current.known.add(m.row));
  if (thread.enabled) {
    translate(msgs, thread.pastMode, true);
    hoverSent(msgs);
  }

  current.observer = new MutationObserver(() => onMutate(threadId));
  current.observer.observe(root, { childList: true, subtree: true });

  for (const f of initHooks) f(current);
}

function onMutate(threadId) {
  if (!current || current.threadId !== threadId) return;
  clearTimeout(current.timer);
  current.timer = setTimeout(() => {
    if (!current || current.threadId !== threadId) return;
    current.onMutate.forEach((f) => f());
    const msgs = readMessages(current.root);
    const { past, fresh } = classifyAdded(msgs, (m) => current.known.has(m.row));
    for (const m of [...past, ...fresh]) current.known.add(m.row);
    if (!current.thread.enabled) return;
    translate(past, current.thread.pastMode, false);
    translate(fresh, current.thread.newMode, true);
    hoverSent([...past, ...fresh]);
  }, DEBOUNCE_MS);
}

export function contextFor(root) {
  return readMessages(root).slice(-CONTEXT_N).map(({ from, text }) => ({ from, text }));
}

// updateLang: true only for the initial scan and fresh arrivals (see Task 12).
async function translate(msgs, mode, updateLang) {
  if (!current) return;
  const todo = msgs.filter((m) => m.from === 'partner' && !isKoreanOnly(m.text));
  if (!todo.length) return;
  const threadId = current.threadId;
  const items = todo.map((m, i) => ({ id: String(i), text: m.text, from: m.from }));
  try {
    const data = await ask({ type: 'incoming', threadId, context: contextFor(current.root), items, updateLang });
    if (current?.threadId !== threadId) return;
    todo.forEach((m, i) => { const r = data[String(i)]; if (r) renderTranslation(m, r.translation, mode); });
    if (updateLang) {
      const t = await ask({ type: 'getThread', threadId }); // partnerLang may have changed
      if (current?.threadId === threadId) current.thread = t;
    }
  } catch (e) {
    if (current?.threadId !== threadId) return;
    if (ERROR_BANNERS[e.kind]) showBanner(ERROR_BANNERS[e.kind]);
    todo.forEach((m) => renderRetry(m, () => translate([m], mode, false)));
  }
}

async function hoverSent(msgs) {
  const mine = msgs.filter((m) => m.from === 'me');
  if (!mine.length || !current) return;
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
  if (current.thread.enabled) translate(msgs, current.thread.pastMode, false); // cache makes this cheap
}

export function showBanner(text) {
  if (bannersShown.has(text)) return;
  bannersShown.add(text);
  const b = document.createElement('div');
  b.style.cssText = 'position:fixed;top:12px;right:12px;z-index:99999;max-width:360px;background:#222;color:#fff;padding:10px 14px;border-radius:8px;font:13px system-ui;cursor:pointer';
  b.textContent = text;
  b.title = 'Click to dismiss';
  b.onclick = () => b.remove();
  document.body.appendChild(b);
}

export const getCurrent = () => current;
```

Notes:
- `rerender` applies `pastMode` to every visible message, so after a toggle change, new ones that arrived earlier switch to past mode. Accepted: a toggle change is a deliberate re-layout.
- Our own `.igt-tr` insertions trigger the observer. `readMessages` returns the same rows, they are all `known`, so nothing re-translates.
- If Instagram recreates a row node, it is unknown again and gets translated again. The cache makes that free; display mode may follow the classification of its position.
- `staleRows` is a `WeakSet`, so removed rows are garbage-collected normally.

**Step 2: Syntax check and tests**

Run: `node --check src/content/main.js && npm test`
Expected: no error; tests PASS.

**Step 3: Commit**

```bash
git add src/content/main.js
git commit -m "feat: thread lifecycle and incoming translation"
```

---

### Task 18: Thread panel

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
    <button type="button" class="fab" title="ig-translate">T</button>
    <div class="p">
      <label>Translate <input type="checkbox" id="enabled"></label>
      <label>Reply in <select id="outputLang"></select></label>
      <label>Other languages to <select id="otherTarget"><option value="ko">Korean</option><option value="en">English</option></select></label>
      <label>Past messages <select id="pastMode"><option value="replace">Replace</option><option value="below">Below</option></select></label>
      <label>New messages <select id="newMode"><option value="below">Below</option><option value="replace">Replace</option></select></label>
      <div>Memo</div>
      <textarea id="memo" placeholder="Who they are, tone, nicknames, running jokes"></textarea>
      <div class="row"><button type="button" id="suggest">Suggest memo</button><button type="button" id="saveMemo">Save memo</button></div>
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
    c.onThreadUpdate.forEach((f) => f(c.thread)); // e.g. outgoing resets its preview when disabled
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

Load the panel before the first `tick()`, so the hook exists before any `initThread` runs:

```js
export async function start() {
  const { mountPanel } = await import('./panel.js');
  initHooks.push(mountPanel);
  let lastPath = null;
  // ... rest of the existing body unchanged
}
```

The import is dynamic because `panel.js` imports from `main.js`. By the time `start()` runs, `main.js` has finished evaluating, so the cycle is safe. Task 20 replaces this with one combined import of `panel.js` and `outgoing.js`.

**Step 3: Syntax check and tests**

Run: `node --check src/content/panel.js && node --check src/content/main.js && npm test`
Expected: PASS.

**Step 4: Commit**

```bash
git add src/content/panel.js src/content/main.js
git commit -m "feat: per-thread panel with toggles and memo"
```

---

### Task 19: Live check, incoming (manual)

**Safety:** no sending, no typing in the Instagram composer.

**Step 1:** Ask the user to reload the extension at `chrome://extensions` and reload the Instagram tab.

**Step 2:** Using Claude in Chrome, open the test thread `https://www.instagram.com/direct/t/17843292048580540/`. Its partner is the user's own second account. If the thread has no non-Korean messages yet, ask the user to send a few from that account first. Check:
- [ ] past partner messages are replaced by Korean, with the original on hover
- [ ] own messages are untouched
- [ ] the panel button appears; toggling "Past messages" to Below re-renders
- [ ] toggling "Other languages to" English re-renders non-English messages (for example Russian) in English, while English messages stay Korean
- [ ] scrolling up loads history, and that history is translated in past mode
- [ ] switching to another thread tears down the panel and translations, then sets up the new thread
- [ ] switching A to B to A quickly leaves exactly one panel button, and translations appear within about 2 s of each switch (about 10 s means Instagram reuses row nodes; see the Task 17 notes)
- [ ] scrolling up to load history does not change `partnerLang` (compare `t:<id>` before and after)
- [ ] the service worker console has no errors
- [ ] in the panel, `Reply in` is still Auto, and `chrome.storage.local` `t:<id>` shows `partnerLang` set

**Step 3:** Ask the user to send a message from the second account while the thread is open. Check that it is translated **below** the bubble.

**Step 4:** Record pass/fail per item in `docs/spike-notes.md` under `## Live check: incoming`. Fix any selector issue in `selectors.js`, plus the snapshot test if needed. Commit.

```bash
git add -A
git commit -m "test: live incoming check recorded"
```

---

# Sprint 5: Outgoing preview

### Task 20: Composer write helpers and key interception

**Files:**
- Modify: `src/content/dom.js` (append composer helpers)
- Create: `src/content/outgoing.js`
- Modify: `src/content/main.js` (`start()` loads `outgoing.js`)

**Step 1: Append composer helpers to `src/content/dom.js`**

Use exactly the sequence that worked in Task 3 Step 4. The default, `execCommand` `selectAll` then `insertText`:

```js
export function getComposerText(el) {
  return (el.innerText || '').replace(/\n$/, '');
}

export function setComposerText(el, text) {
  el.focus();
  el.ownerDocument.execCommand('selectAll', false);
  if (text) el.ownerDocument.execCommand('insertText', false, text);
  else el.ownerDocument.execCommand('delete', false);
}
```

If the spike found that only the synthetic paste works, the body becomes: `focus`, `execCommand('selectAll')`, `execCommand('delete')`, then dispatch the `ClipboardEvent('paste')` from Task 3 with `text`.

**Step 2: Write `src/content/outgoing.js`**

```js
import { initial, reduce } from '../lib/preview.js';
import { hasHangul, langName, LANG_NAMES } from '../lib/lang.js';
import { findComposer, getComposerText, setComposerText } from './dom.js';
import { ask, getCurrent, contextFor, showBanner } from './main.js';

const COMPOSE_ENTER_MS = 300; // a deferred IME Enter must be followed by compositionend within this window
const WRITE_SETTLE_MS = 50;   // editors such as Lexical commit DOM updates asynchronously
const norm = (s) => s.replace(/\s+/g, ' ').trim();
const isEnter = (e) => e.key === 'Enter' || e.code === 'Enter' || e.code === 'NumpadEnter';
const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');
const block = (e) => { e.preventDefault(); e.stopImmediatePropagation(); };

export function mountOutgoing(cur) {
  let state = initial();
  let note = null;
  let enterAfterComposition = null; // { hard, at }
  let lastText = ''; // composer text while previewing; recorded if Instagram's Send button sends it
  let writing = false; // our own composer writes fire input events; ignore them

  const composer = () => findComposer(document);
  const text = (s) => document.createTextNode(s);
  const write = (c, s) => { writing = true; try { setComposerText(c, s); } finally { writing = false; } };

  // Composer selector check (design: selector miss = inactive + badge).
  setTimeout(() => {
    if (getCurrent() === cur && !composer()) {
      ask({ type: 'badge', text: '!' }).catch(() => {});
      console.warn('[igt] composer not found; outgoing translation inactive');
    }
  }, 3000);

  const showNote = (nodes, isError) => {
    const c = composer();
    if (!c) return;
    if (!note) {
      note = document.createElement('div');
      note.className = 'igt-composer-note';
      // Above the composer's row so Instagram's own layout stays intact.
      (c.closest('form, [role="group"]') || c.parentElement).before(note);
    }
    note.classList.toggle('igt-error', !!isError);
    note.replaceChildren(...nodes);
  };
  const hideNote = () => { note?.remove(); note = null; };

  const chip = (lang) => {
    const b = document.createElement('button');
    b.type = 'button';
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

  function resetPreview() {
    dispatch({ type: 'reset' });
    hideNote();
    lastText = '';
  }

  async function apply(effect) {
    const c = composer();
    switch (effect.type) {
      case 'translate': {
        showNote([text(effect.profile === 'hard' ? 'Translating (hard)...' : 'Translating...')]);
        try {
          const cur2 = getCurrent();
          if (!cur2) throw new Error('thread closed');
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
        if (!c) { resetPreview(); break; }
        write(c, effect.translation);
        await new Promise((r) => setTimeout(r, WRITE_SETTLE_MS));
        if (state.mode !== 'preview') break; // Esc or reset meanwhile
        if (norm(getComposerText(c)) !== norm(effect.translation)) {
          dispatch({ type: 'reset' });
          showNote([text('Could not write the translation into the message box. Nothing was sent.')], true);
          break;
        }
        lastText = effect.translation;
        showNote([text(`${effect.back_translation}  · ${modelLabel(effect.model)}`), chip(effect.lang)]);
        break;
      }
      case 'restore':
        if (c) write(c, effect.korean);
        hideNote();
        lastText = '';
        break;
      case 'sent': {
        // Runs synchronously inside the Enter keydown, before Instagram reads and clears the composer.
        const cur2 = getCurrent();
        const sentText = c ? getComposerText(c).trim() : '';
        hideNote();
        lastText = '';
        if (cur2 && sentText) ask({ type: 'sent', threadId: cur2.threadId, text: sentText, korean: effect.korean }).catch(() => {});
        break;
      }
      case 'fail':
        if (c && effect.korean != null && norm(getComposerText(c)) !== norm(effect.korean)) write(c, effect.korean);
        lastText = '';
        showNote([text(`Translation failed: ${effect.message}`)], true);
        break;
    }
  }

  function dispatch(event) {
    const r = reduce(state, event);
    state = r.state;
    apply(r.effect);
    return r.effect;
  }

  // Composer emptied while previewing: Instagram's Send button sent it, or the user deleted it.
  function checkEmpty() {
    if (state.mode !== 'preview') return;
    const c = composer();
    if (!c || getComposerText(c).trim() !== '') return;
    const cur2 = getCurrent();
    if (cur2 && lastText.trim()) {
      ask({ type: 'sent', threadId: cur2.threadId, text: lastText.trim(), korean: state.korean }).catch(() => {});
    }
    resetPreview();
  }

  function onInput(e) {
    const c = composer();
    if (writing || state.mode !== 'preview' || !c || !c.contains(e.target)) return;
    const t = getComposerText(c);
    if (t.trim()) lastText = t; else checkEmpty();
  }

  function onKeyDown(e) {
    const cur2 = getCurrent();
    if (!cur2?.thread.enabled) return;
    const c = composer();

    if (!c || !c.contains(e.target)) {
      // Composer selector broken: never let Hangul go out untranslated by accident.
      if (!c && isEnter(e) && !e.shiftKey && e.target?.isContentEditable
          && hasHangul(e.target.innerText || e.target.textContent || '')) {
        block(e);
        showBanner('ig-translate: message box not recognised, so nothing was sent. The selectors need updating.');
      }
      return;
    }

    if (e.key === 'Escape') {
      const eff = dispatch({ type: 'esc' });
      if (eff.type !== 'pass') block(e);
      return;
    }
    if (!isEnter(e) || e.shiftKey) return;

    // Korean IME: Enter mid-composition. Never let it reach Instagram while a translation is pending
    // or while the box holds Hangul; handle the Enter once the composition is committed.
    if (e.isComposing || e.keyCode === 229) {
      if (state.mode === 'translating') { block(e); return; }
      if (hasHangul(getComposerText(c)) && !(state.mode === 'preview' && state.lang === 'ko')) {
        block(e);
        enterAfterComposition = { hard: e.altKey, at: Date.now() };
      }
      return;
    }

    const eff = dispatch({ type: 'enter', text: getComposerText(c), hard: e.altKey });
    // 'sent' lets the real Enter through so Instagram sends the composer text itself.
    if (eff.type !== 'pass' && eff.type !== 'sent') block(e);
  }

  function onCompositionEnd() {
    const pending = enterAfterComposition;
    enterAfterComposition = null;
    if (!pending || Date.now() - pending.at > COMPOSE_ENTER_MS) return;
    // Let the committed text land in the composer first.
    setTimeout(() => {
      const c = composer();
      if (c) dispatch({ type: 'enter', text: getComposerText(c), hard: pending.hard });
    }, 0);
  }

  window.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('compositionend', onCompositionEnd, true);
  window.addEventListener('input', onInput, true);
  cur.onMutate.push(checkEmpty);
  cur.onThreadUpdate.push((t) => { if (!t.enabled && state.mode !== 'idle') resetPreview(); });
  cur.onTeardown.push(() => {
    window.removeEventListener('keydown', onKeyDown, true);
    window.removeEventListener('compositionend', onCompositionEnd, true);
    window.removeEventListener('input', onInput, true);
    resetPreview();
  });
}
```

How this fits the design and the plan review:
- Listeners sit on `window` in the capture phase, so they run before Instagram's handlers on the composer.
- If Chrome fires a second, non-composing Enter after the composing one (see the Task 3 IME log), that Enter reaches `reduce` while in `translating`, gets `block`, and nothing double-fires.
- A deferred IME Enter runs outside any key event, so a `pass` or `sent` effect from it does nothing. That cannot happen: it is only set up when the box holds Hangul, which always yields `translate`.
- **Stuck preview:** a Send-button send or a cleared box is caught by `checkEmpty` through two paths, the composer `input` event and the thread observer (`onMutate`). The observer covers Instagram clearing the editor without an input event. New Korean typed while in preview is a new draft (reducer rule), never a raw send.
- `write()` sets `writing` so the input events our own writes cause (an intermediate empty box with the paste variant) never look like a user clearing the box.
- A failed write into the composer is detected after the editor settles, and nothing is left in `preview`.
- Turning "Translate" off in the panel resets any preview (`onThreadUpdate`).
- `NumpadEnter` and `key === 'Process'` with `code === 'Enter'` (some IMEs) both count as Enter.
- With `Alt+Enter`, check in Task 21 that Instagram does not treat `Alt+Enter` as send by itself. Our capture listener blocks it either way, except for `pass`. A non-Hangul `Alt+Enter` passes through untouched, which is fine.

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

### Task 21: Live check, outgoing (manual, user presses send)

**Safety: the user does every keypress in this task.** Claude only observes with `read_page` and screenshots, and never types into or submits the Instagram composer.

**Step 1:** Reload the extension and the tab. The user opens the test thread `https://www.instagram.com/direct/t/17843292048580540/` (partner = the user's own second account).

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

**Step 8:** Send-button case: the user previews a Korean draft, then clicks Instagram's Send button instead of pressing Enter. Check:
- [ ] exactly one message is sent (the translation)
- [ ] the note disappears
- [ ] hovering the new bubble shows the Korean

**Step 9:** New-draft case: the user previews a draft, clears the box, types a different Korean sentence and presses Enter. Check: a new preview appears for the new sentence, and nothing was sent.

**Step 10:** Host failure case: Claude runs `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{,.off} && pkill -f '[i]g_translate_host.py'`. The user presses Enter on Korean text. Check:
- [ ] after about 3 s the Korean is still in the composer
- [ ] the error note names the host
- [ ] nothing is sent

Then Claude restores the manifest with `mv ~/.config/google-chrome/NativeMessagingHosts/com.northprot.ig_translate.json{.off,}`.

**Step 11:** Record results in `docs/spike-notes.md` under `## Live check: outgoing`. Fix any failures, then commit.

```bash
git add -A
git commit -m "test: live outgoing check recorded"
```

---

# Sprint 6: Fixture eval

### Task 22: Fixture set and eval script

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

Node calls the API directly (Node sends no `Origin`, so CORS rules do not apply). It reuses `api.js` and `prompts.js` through a small `fetch` transport.

```js
// Usage:
//   ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)" \
//   ANTHROPIC_WORKSPACE_ID="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/anthropic/configs/default.json")))["workspace_id"])')" \
//   node scripts/eval-fixtures.mjs [--hard]
import { readFileSync } from 'node:fs';
import { callJson } from '../src/lib/api.js';
import { buildIncomingRequest, buildOutgoingRequest, parseIncoming, parseOutgoing } from '../src/lib/prompts.js';

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

const hard = process.argv.includes('--hard');
const cases = JSON.parse(readFileSync(new URL('./fixtures/conversations.json', import.meta.url)));
let failures = 0;

for (const c of cases) {
  console.log(`\n=== ${c.name}`);
  const t0 = Date.now();
  const inc = await callJson(buildIncomingRequest({
    model: 'claude-sonnet-5-5', memo: c.memo, context: c.context, otherTarget: c.otherTarget,
    items: c.items.map(({ id, text }) => ({ id, text })),
  }), parseIncoming, { transport });
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
  }), parseOutgoing, { transport });
  console.log(`outgoing ${Date.now() - t1}ms\n  ${c.outgoing.korean}\n  -> ${out.translation}\n  <- ${out.back_translation}`);
}
console.log(`\n${failures} src_lang failure(s)`);
process.exit(failures ? 1 : 0);
```

**Step 3: Run it**

Run the usage command from the script header (it reads the key and workspace inside the command and never prints them).
Expected: `0 src_lang failure(s)`, plus a latency per call. Show the translations to the user for an eye check.

Run it again with `--hard`.
Expected: same, with Opus for outgoing.

**Step 4:** If the user flags tone problems, adjust the system prompts in `src/lib/prompts.js`, then re-run Task 7's tests and this script.

**Step 5: Commit**

```bash
git add scripts/fixtures/conversations.json scripts/eval-fixtures.mjs src/lib/prompts.js
git commit -m "test: fixture eval for prompts and parsing"
```
