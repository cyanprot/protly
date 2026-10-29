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
