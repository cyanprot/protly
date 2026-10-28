import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { createInstance } from '../src/generic/instance.js';
import { ERRORS } from '../src/ui/errors.js';
import { _resetToasts } from '../src/ui/toast.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 1500) {
  const end = Date.now() + ms;
  while (!fn()) { if (Date.now() > end) throw new Error('timed out'); await sleep(5); }
}
const reply = (translation, back = '역번역', model = 'claude-sonnet-5-5', lang = 'en') =>
  ({ translation, back_translation: back, model, lang });

function setup(html = '<textarea id="b"></textarea>') {
  _resetToasts();
  const dom = new JSDOM(`<body>${html}</body>`, { url: 'https://forum.example.org/post' });
  const doc = dom.window.document;
  const calls = [];
  const pending = [];
  const ask = (msg) => { calls.push(msg); return new Promise((res, rej) => pending.push({ res, rej })); };
  const inst = createInstance({ doc, ask, fonts: null });
  const root = () => doc.querySelector('.pl-card')?.shadowRoot;
  const msg = () => root()?.querySelector('.msg')?.textContent ?? null;
  const btn = (label) => [...(root()?.querySelectorAll('button') || [])].find((b) => b.textContent === label);
  const toasts = () => doc.querySelector('.pl-toasts')?.shadowRoot?.textContent ?? '';
  const box = doc.getElementById('b');
  return { dom, doc, calls, pending, inst, root, msg, btn, toasts, box };
}

test('Korean in a textarea: box call with the hostname, write, preview, Undo restores', async () => {
  const { calls, pending, inst, msg, btn, root, box } = setup();
  box.value = '내일 봐';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  assert.deepEqual(calls[0], { type: 'box', text: '내일 봐', lang: 'en', profile: 'outgoing', hostname: 'forum.example.org' });
  assert.match(msg(), /Translating/);
  pending[0].res(reply('see you tomorrow', '내일 봐'));
  await until(() => box.value === 'see you tomorrow');
  await until(() => btn('Undo'));
  assert.match(msg(), /내일 봐/);
  assert.ok(btn('Opus'));
  assert.ok(root().querySelector('select.pl-chip'));
  btn('Undo').click();
  await until(() => box.value === '내일 봐');
  assert.equal(root(), undefined);
});

test('English: polish call, no language chip', async () => {
  const { calls, pending, inst, root, btn, box } = setup();
  box.value = 'i has a question';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  assert.deepEqual(calls[0], { type: 'polish', text: 'i has a question', profile: 'polish' });
  pending[0].res({ translation: 'I have a question', back_translation: '문법', model: 'claude-sonnet-5-5' });
  await until(() => btn('Undo'));
  assert.equal(root().querySelector('select.pl-chip'), null);
});

test('a prefix picks the language and drops the prefix', async () => {
  const { calls, inst, box } = setup();
  box.value = 'ru: 안녕';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  assert.equal(calls[0].lang, 'ru');
  assert.equal(calls[0].text, '안녕');
});

test('Alt+T again while the preview is open re-runs on Opus', async () => {
  const { calls, pending, inst, btn, box } = setup();
  box.value = '내일 봐';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  pending[0].res(reply('see you tomorrow'));
  await until(() => btn('Undo'));
  inst.run({ source: 'command' });
  await until(() => calls.length === 2);
  assert.equal(calls[1].profile, 'hard');
  assert.equal(calls[1].text, '내일 봐'); // the original, not the shown translation
});

test('Esc in the box during the preview undoes', async () => {
  const { dom, calls, pending, inst, btn, box } = setup();
  box.value = '내일 봐';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  pending[0].res(reply('see you tomorrow'));
  await until(() => btn('Undo'));
  box.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  await until(() => box.value === '내일 봐');
});

test('text typed while working: the result is dropped, the box is left alone', async () => {
  const { calls, pending, inst, msg, box } = setup();
  box.value = '내일 봐';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  box.value = '내일 봐 ㅋㅋ';
  pending[0].res(reply('see you tomorrow'));
  await until(() => /dropped/.test(msg() || ''));
  assert.equal(box.value, '내일 봐 ㅋㅋ');
});

test('an auth error shows in the card and as a page toast', async () => {
  const { calls, pending, inst, msg, toasts, box } = setup();
  box.value = '내일 봐';
  box.focus();
  inst.run({ source: 'command' });
  await until(() => calls.length === 1);
  pending[0].rej(Object.assign(new Error('401'), { kind: 'auth' }));
  await until(() => msg() === ERRORS.auth);
  assert.match(toasts(), /API key missing/);
  assert.equal(box.value, '내일 봐');
});

test('nothing focused and nothing selected: a toast, no call', async () => {
  const { calls, inst, toasts } = setup('<p>text</p>');
  await inst.run({ source: 'command' });
  assert.match(toasts(), /Put the cursor in a text box or select text\./);
  assert.equal(calls.length, 0);
});

test('menu selection: Korean gets a toast, other text a popover with the translation', async () => {
  const { calls, pending, inst, msg, btn, toasts } = setup('<p>text</p>');
  await inst.run({ source: 'menu-selection', selectionText: '안녕하세요' });
  assert.match(toasts(), /Already Korean\./);
  assert.equal(calls.length, 0);
  inst.run({ source: 'menu-selection', selectionText: 'see you' });
  await until(() => calls.length === 1);
  assert.deepEqual(calls[0], { type: 'selection', text: 'see you' });
  pending[0].res({ src_lang: 'en', translation: '또 봐' });
  await until(() => msg() === '또 봐');
  assert.ok(btn('Close'));
});

test('toast() shows a message in the page', () => {
  const { inst, toasts } = setup('<p>x</p>');
  inst.toast('protly cannot reach this frame.');
  assert.match(toasts(), /cannot reach this frame/);
});
