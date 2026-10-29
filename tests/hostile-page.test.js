// A hostile page: its scripts share the DOM with protly's UI, and its text reaches protly's renderers.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { createCard, shadowOf } from '../src/ui/card.js';

test('page scripts cannot reach into the card: its shadow root is closed', () => {
  const doc = new JSDOM('<body><div id="row"></div></body>').window.document;
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  card.preview({ text: '역번역', model: 'claude-opus-5-5', lang: 'ru', onLang: () => {}, actions: [{ label: 'Opus', onClick: () => {} }] });
  const host = doc.querySelector('.pl-card');
  assert.equal(host.shadowRoot, null); // what page JS sees
  assert.equal(shadowOf(host).querySelector('.msg').textContent, '역번역'); // protly's own handle
});

test('page scripts cannot read or drive the thread panel: its shadow root is closed', async () => {
  const win = new JSDOM('<body></body>').window;
  globalThis.document = win.document;
  globalThis.window = win;
  globalThis.Option = win.Option;
  globalThis.chrome = { runtime: { id: 'x', sendMessage: async () => assert.fail('no message expected') } };
  const { mountPanel } = await import('../src/content/panel.js');
  const cur = { thread: { enabled: true, outputLang: 'auto', otherTarget: 'ko', pastMode: 'replace', newMode: 'below', memo: 'private memo' }, onTeardown: [] };
  mountPanel(cur);
  const host = [...win.document.body.children].find((e) => e.style.zIndex === '99998');
  assert.ok(host);
  assert.equal(host.shadowRoot, null);
  assert.equal(win.document.body.textContent.includes('private memo'), false);
  cur.onTeardown.forEach((f) => f());
});

test('a sent message that reads like an Object method gets no inherited hover title', async () => {
  const { sentOriginal } = await import('../src/content/main.js');
  const map = JSON.parse('{"hi":"안녕","__proto__":"원문"}'); // as structured clone delivers it: own keys
  assert.equal(sentOriginal(map, 'hi'), '안녕');
  assert.equal(sentOriginal(map, '__proto__'), '원문');
  for (const t of ['constructor', 'toString', 'hasOwnProperty', 'nope']) assert.equal(sentOriginal(map, t), null, t);
});

// Page and model text that looks like markup or script, plus bidi overrides and zero-width characters.
const HOSTILE = [
  '<img src=x onerror="globalThis.pwned=1">',
  '<script>globalThis.pwned=1</script>',
  '"><svg onload=alert(1)><a href="javascript:alert(1)">x</a>',
  '‮gnp.exe‬ and ⁦isolate⁩',
  'zero​width‌‍join﻿',
  'שלום עולם · مرحبا بالعالم',
  '${constructor.constructor("return this")()} {{7*7}} %s %o',
  '&lt;b&gt;already escaped&lt;/b&gt; &amp;',
];
const ELEMENT_TAGS = (root) => [...root.querySelectorAll('*')].map((e) => e.tagName.toLowerCase());

test('card: page or model text is shown as text, character for character', () => {
  const doc = new JSDOM('<body><div id="row"></div></body>').window.document;
  for (const s of HOSTILE) {
    const card = createCard({ doc, place: { before: doc.getElementById('row') } });
    card.preview({ text: s, model: s, lang: 'xx', onLang: () => {}, actions: [{ label: s, onClick: () => {} }], hints: s });
    const root = shadowOf(card.host).querySelector('.pl-root');
    assert.equal(root.querySelector('.msg').textContent, s);
    assert.equal(root.querySelector('button').textContent, s);
    assert.equal(root.querySelector('.hints').textContent, s);
    assert.deepEqual(ELEMENT_TAGS(root).filter((t) => !['span', 'select', 'option', 'button'].includes(t)), []);
    card.message(s, { error: true });
    assert.equal(root.querySelector('.msg').textContent, s);
    card.working(s);
    assert.ok(root.textContent.startsWith(s.replace(/(\.\.\.|…)$/, '')));
    card.hide();
  }
});

test('toast: page or model text is shown as text', async () => {
  const { showToast, _resetToasts } = await import('../src/ui/toast.js');
  const doc = new JSDOM('<body></body>').window.document;
  _resetToasts();
  for (const s of HOSTILE) {
    const t = showToast(s, { doc, transient: false });
    assert.equal(t.querySelector('.msg').textContent, s);
    assert.deepEqual(ELEMENT_TAGS(t), ['span', 'span']);
  }
});

test('Instagram rows: a hostile translation, original or hover text never becomes markup', async () => {
  const { renderTranslation, renderRetry, setHoverOriginal, clearAllTranslations } = await import('../src/content/dom.js');
  const doc = new JSDOM('<body><div id="root"><div class="row"><div dir="auto">x</div></div></div></body>').window.document;
  const textEl = doc.querySelector('[dir="auto"]');
  for (const s of HOSTILE) {
    for (const mode of ['replace', 'below']) {
      const m = { row: textEl.parentElement, textEl, text: s };
      renderTranslation(m, s, mode);
      const tr = textEl.nextElementSibling;
      assert.equal(tr.textContent, s);
      assert.equal(tr.children.length, 0);
      if (mode === 'replace') assert.equal(tr.title, s);
      renderRetry(m, () => {});
      assert.equal(textEl.nextElementSibling.tagName, 'BUTTON');
      setHoverOriginal(m, s);
      assert.equal(textEl.getAttribute('title'), s);
    }
  }
  clearAllTranslations(doc.getElementById('root'));
  assert.equal(doc.querySelectorAll('.pl-tr, img, script, svg, a').length, 0);
});

test('Gmail: a hostile translation goes into the body as text lines', async () => {
  const { textToNodes, nodesToText } = await import('../src/content/gmail/body.js');
  const doc = new JSDOM('<body></body>').window.document;
  const text = HOSTILE.join('\n');
  const nodes = textToNodes(doc, `${text}\r\n\r\nend`);
  for (const n of nodes) {
    assert.equal(n.tagName, 'DIV');
    assert.ok([...n.childNodes].every((c) => c.nodeType === 3 || c.tagName === 'BR'));
  }
  assert.equal(nodesToText(nodes), `${text}\n\nend`);
});

test('Gmail: a hostile email in the thread is read as text; its markup stays inert', async () => {
  const { readThread } = await import('../src/content/gmail/thread.js');
  const dom = new JSDOM(`<body><div role="main"><div role="listitem">
    <h3><span email="them@example.com">Them</span></h3>
    <div class="a3s"><div>Hello ‮dlrow<img src="x" onerror="globalThis.pwned=1"></div><script>globalThis.pwned=2</script>
    <div>zero​width</div><blockquote>quoted <b>old</b></blockquote></div>
  </div></div></body>`, { runScripts: 'outside-only' });
  const [msg] = readThread(dom.window.document.querySelector('[role="main"]'), 'me@example.com');
  assert.equal(msg.from, 'them');
  assert.match(msg.text, /^Hello ‮dlrow\n/);
  assert.match(msg.text, /zero​width/);
  assert.doesNotMatch(msg.text, /quoted/);
  assert.equal(dom.window.pwned, undefined);
});

test('generic box: hostile text round-trips through a textarea exactly, and contenteditable gets insertText', async () => {
  const { readBox, writeBox } = await import('../src/generic/writer.js');
  const doc = new JSDOM('<body><textarea></textarea><div contenteditable="true">x</div></body>').window.document;
  const ta = { el: doc.querySelector('textarea'), doc, kind: 'text' };
  for (const s of HOSTILE) {
    assert.equal(await writeBox(ta, s, { verifyMs: 0 }), true);
    assert.equal(readBox(ta), s);
  }
  const ce = { el: doc.querySelector('[contenteditable]'), doc, kind: 'contenteditable' };
  const calls = [];
  doc.execCommand = (cmd, ui, value) => { calls.push(cmd); ce.el.textContent = value; return true; };
  for (const s of HOSTILE) assert.equal(await writeBox(ce, s, { settleMs: 0, verifyMs: 0 }), true);
  assert.deepEqual([...new Set(calls)], ['insertText']); // never insertHTML
  assert.equal(ce.el.children.length, 0);
});

test('very long page text: the any-site path refuses it before any request', async () => {
  const { createInstance } = await import('../src/generic/instance.js');
  const dom = new JSDOM(`<body><textarea></textarea></body>`, { pretendToBeVisual: true });
  const doc = dom.window.document;
  const asks = [];
  const inst = createInstance({ doc, ask: async (m) => { asks.push(m); return {}; }, hostname: 'evil.example' });
  const ta = doc.querySelector('textarea');
  ta.value = '안녕'.repeat(5000) + '​'.repeat(1000);
  ta.focus();
  globalThis.document = doc;
  await inst.run({ source: 'command' });
  await inst.run({ source: 'menu-selection', selectionText: 'a'.repeat(100000) });
  assert.equal(asks.length, 0);
  assert.match(doc.querySelector('.pl-toasts')?.shadowRoot?.textContent ?? '', /Too long/);
});
