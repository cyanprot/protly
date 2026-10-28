import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { GSEL } from '../src/content/gmail/selectors.js';
import { userNodes, nodesToText } from '../src/content/gmail/body.js';
import { mountCompose, translate, undo } from '../src/content/gmail/compose.js';

const html = readFileSync(new URL('./fixtures/gmail.html', import.meta.url), 'utf8');
const KOREAN = '한글 첫줄\n둘째 줄\n\n셋째 문단';
const flush = () => new Promise((r) => setTimeout(r, 0));
const ok = (translation, model = 'claude-sonnet-5-5') =>
  ({ ok: true, data: { lang: 'en', translation, back_translation: '역번역', model } });

// compose.js reads the page through the globals document and chrome; each test gets a fresh page.
function setup() {
  globalThis.document = new JSDOM(`<body>${html}</body>`).window.document;
  const calls = [];
  const pending = [];
  globalThis.chrome = {
    runtime: {
      sendMessage: (msg) => {
        if (msg.type === 'badge') return Promise.resolve({ ok: true, data: true });
        calls.push(msg);
        return new Promise((res) => pending.push(res));
      },
    },
  };
  const [inline, dialog] = document.querySelectorAll(GSEL.body);
  const reply = async (r) => { pending.shift()(r); await flush(); };
  const note = () => document.querySelector('.igt-g-note');
  const buttonIn = (label) => [...(note()?.querySelectorAll('button') || [])].find((b) => b.textContent === label);
  return { inline, dialog, calls, reply, note, buttonIn };
}
const userText = (body) => nodesToText(userNodes(body));

test('the button mounts next to each compose\'s own Send, once', () => {
  const { inline, dialog } = setup();
  mountCompose(inline);
  mountCompose(inline);
  mountCompose(dialog);
  assert.equal(inline.closest('.reply').querySelectorAll('.igt-g-btn').length, 1);
  assert.equal(dialog.closest('[role="dialog"]').querySelectorAll('.igt-g-btn').length, 1);
});

test('a body whose toolbar renders later gets its button on a later scan', () => {
  setup();
  const box = document.createElement('div');
  const body = document.createElement('div');
  body.setAttribute('role', 'textbox');
  body.setAttribute('aria-label', 'Message Body');
  body.setAttribute('contenteditable', 'true');
  box.appendChild(body);
  document.body.appendChild(box);
  mountCompose(body);
  assert.equal(box.querySelector('.igt-g-btn'), null);
  const table = document.createElement('table');
  table.setAttribute('role', 'group');
  const td = table.insertRow().insertCell();
  const send = document.createElement('div');
  send.setAttribute('role', 'button');
  send.setAttribute('data-tooltip', 'Send (Ctrl-Enter)');
  td.appendChild(send);
  box.appendChild(table);
  mountCompose(body);
  assert.ok(box.querySelector('.igt-g-btn'));
});

test('translate replaces the user part, Undo brings the Korean back, signature untouched', async () => {
  const { inline, calls, reply, note, buttonIn } = setup();
  const sig = inline.querySelector('.gmail_signature');
  translate(inline);
  assert.match(note().textContent, /Translating/);
  assert.equal(calls[0].korean, KOREAN);
  assert.equal(calls[0].context.length, 2); // inline reply: thread context
  await reply(ok('Line one\nLine two'));
  assert.equal(userText(inline), 'Line one\nLine two');
  assert.match(note().textContent, /역번역/);
  buttonIn('Undo').click();
  assert.equal(userText(inline), KOREAN);
  assert.equal(inline.querySelector('.gmail_signature'), sig);
  assert.equal(note(), null);
});

test('a new compose window sends no thread context', () => {
  const { dialog, calls } = setup();
  dialog.replaceChildren(document.createTextNode('새 메일'));
  translate(dialog);
  assert.deepEqual(calls[0].context, []);
});

test('typing while translating drops the result and keeps the typing', async () => {
  const { inline, reply, note } = setup();
  translate(inline);
  inline.firstChild.textContent += ' 추가';
  await reply(ok('Translated'));
  assert.equal(userText(inline), KOREAN.replace('한글 첫줄', '한글 첫줄 추가'));
  assert.match(note().textContent, /draft changed/);
});

test('Cancel ends translating and the late result is ignored', async () => {
  const { inline, reply, note, buttonIn } = setup();
  translate(inline);
  buttonIn('Cancel').click();
  assert.equal(note(), null);
  await reply(ok('Late'));
  assert.equal(userText(inline), KOREAN);
  assert.equal(note(), null);
});

test('a failure keeps the Korean and names the problem', async () => {
  const { inline, reply, note } = setup();
  translate(inline);
  await reply({ ok: false, error: { kind: 'host', message: 'port closed' } });
  assert.equal(userText(inline), KOREAN);
  assert.match(note().textContent, /Native host not reachable/);
});

test('a failed Opus retry keeps the preview controls', async () => {
  const { inline, reply, note, buttonIn } = setup();
  translate(inline);
  await reply(ok('First'));
  buttonIn('Opus').click();
  await reply({ ok: false, error: { kind: 'timeout', message: 'slow' } });
  assert.equal(userText(inline), 'First');
  assert.match(note().textContent, /too long/);
  assert.ok(buttonIn('Opus') && buttonIn('Undo') && note().querySelector('select'));
  buttonIn('Undo').click();
  assert.equal(userText(inline), KOREAN);
});

test('Opus after editing the translation asks before replacing the edit', async () => {
  const { inline, calls, reply, note, buttonIn } = setup();
  translate(inline);
  await reply(ok('First'));
  inline.firstChild.textContent = 'First, edited';
  buttonIn('Opus').click();
  assert.equal(calls.length, 1); // nothing sent yet
  assert.match(note().textContent, /You edited the translation/);
  buttonIn('Replace anyway').click();
  assert.equal(calls.length, 2);
  assert.equal(calls[1].profile, 'hard');
  assert.equal(calls[1].korean, KOREAN);
  await reply(ok('Second', 'claude-opus-5-5'));
  assert.equal(userText(inline), 'Second');
  assert.match(note().textContent, /Opus/);
  undo(inline);
  assert.equal(userText(inline), KOREAN); // Undo still goes back to the original Korean
});
