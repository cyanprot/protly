import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { GSEL } from '../src/content/gmail/selectors.js';
import { userNodes, nodesToText } from '../src/content/gmail/body.js';
import { mountCompose, translate, undo, escape } from '../src/content/gmail/compose.js';
import { flags } from '../src/lib/flags.js';

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
  // The card renders in an open shadow root; its .pl-root holds the text, buttons and picker.
  const note = () => document.querySelector('.pl-card')?.shadowRoot.querySelector('.pl-root') ?? null;
  const buttonIn = (label) => [...(note()?.querySelectorAll('button') || [])].find((b) => b.textContent === label);
  return { inline, dialog, calls, reply, note, buttonIn };
}
const userText = (body) => nodesToText(userNodes(body));
const ENGLISH = 'Hi Prof. Allen,\nI has a question.\n\nThanks,\nCyan';
const polished = (translation, model = 'claude-sonnet-5-5') =>
  ({ ok: true, data: { translation, back_translation: '바뀐 점', model } }); // polish returns no lang
const draft = (body, text) => body.replaceChildren(document.createTextNode(text));
// Runs a test with Polish English on and always turns it off again.
const withPolish = (fn) => async () => { flags.polish = true; try { await fn(); } finally { flags.polish = false; } };

test('the button mounts next to each compose\'s own Send, once', () => {
  const { inline, dialog } = setup();
  mountCompose(inline);
  mountCompose(inline);
  mountCompose(dialog);
  assert.equal(inline.closest('.reply').querySelectorAll('.pl-g-btn').length, 1);
  assert.equal(dialog.closest('[role="dialog"]').querySelectorAll('.pl-g-btn').length, 1);
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
  assert.equal(box.querySelector('.pl-g-btn'), null);
  const table = document.createElement('table');
  table.setAttribute('role', 'group');
  const td = table.insertRow().insertCell();
  const send = document.createElement('div');
  send.setAttribute('role', 'button');
  send.setAttribute('data-tooltip', 'Send (Ctrl-Enter)');
  td.appendChild(send);
  box.appendChild(table);
  mountCompose(body);
  assert.ok(box.querySelector('.pl-g-btn'));
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

test('the button title mentions polish, the label stays Translate', () => {
  const { inline } = setup();
  mountCompose(inline);
  const btn = inline.closest('.reply').querySelector('.pl-g-btn');
  assert.equal(btn.textContent, 'Translate');
  assert.match(btn.title, /polish an English one/);
});

test('polish on: an English draft gets one polish call, Undo restores the English', withPolish(async () => {
  const { dialog, calls, reply, note, buttonIn } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  assert.match(note().textContent, /^Polishing/);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], { type: 'polish', text: ENGLISH, profile: 'email' });
  await reply(polished('Hi Prof. Allen,\nI have a question.\n\nThanks,\nCyan'));
  assert.equal(userText(dialog), 'Hi Prof. Allen,\nI have a question.\n\nThanks,\nCyan');
  assert.match(note().textContent, /바뀐 점/);
  buttonIn('Undo').click();
  assert.equal(userText(dialog), ENGLISH);
  assert.equal(note(), null);
}));

test('polish off: an English draft shows an error naming the popup, no call', () => {
  const { dialog, calls, note } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  assert.equal(calls.length, 0);
  assert.match(note().textContent, /Turn on Polish English in the toolbar popup/);
});

test('polish on: digits or emoji only is nothing to polish, no call', withPolish(() => {
  const { dialog, calls, note } = setup();
  draft(dialog, '123 🙂');
  translate(dialog);
  assert.equal(calls.length, 0);
  assert.match(note().textContent, /Nothing to polish/);
}));

test('an English edit in a polish preview is an error, no call, Undo keeps the original', withPolish(async () => {
  const { dialog, calls, reply, note, buttonIn } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  await reply(polished('Polished'));
  draft(dialog, 'Polished, edited');
  translate(dialog);
  assert.equal(calls.length, 1);
  assert.match(note().textContent, /To polish this English, press Undo first/);
  assert.ok(buttonIn('Opus') && buttonIn('Undo'));
  buttonIn('Undo').click();
  assert.equal(userText(dialog), ENGLISH);
}));

test('an English edit in a translate preview is an error with polish on, Undo keeps the Korean', withPolish(async () => {
  const { inline, calls, reply, note, buttonIn } = setup();
  translate(inline);
  await reply(ok('First'));
  inline.firstChild.textContent = 'First, edited';
  translate(inline);
  assert.equal(calls.length, 1);
  assert.match(note().textContent, /press Undo first/);
  buttonIn('Undo').click();
  assert.equal(userText(inline), KOREAN);
}));

test('an English edit in a translate preview with polish off keeps the old error', async () => {
  const { inline, calls, reply, note } = setup();
  translate(inline);
  await reply(ok('First'));
  inline.firstChild.textContent = 'First, edited';
  translate(inline);
  assert.equal(calls.length, 1);
  assert.match(note().textContent, /Use the picker or Opus/);
});

test('a ru: prefix sends lang ru without the prefix, Undo brings back the prefixed draft', async () => {
  const { dialog, calls, reply, buttonIn } = setup();
  draft(dialog, 'ru: 안녕하세요');
  translate(dialog);
  assert.equal(calls[0].type, 'email');
  assert.equal(calls[0].lang, 'ru');
  assert.equal(calls[0].korean, '안녕하세요');
  await reply({ ok: true, data: { lang: 'ru', translation: 'Здравствуйте', back_translation: '안녕하세요', model: 'claude-sonnet-5-5' } });
  assert.equal(userText(dialog), 'Здравствуйте');
  buttonIn('Undo').click();
  assert.equal(userText(dialog), 'ru: 안녕하세요');
});

test('a polish preview has Opus and Undo but no language picker', withPolish(async () => {
  const { dialog, reply, note, buttonIn } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  await reply(polished('Polished'));
  assert.equal(note().querySelector('select'), null);
  assert.ok(buttonIn('Opus') && buttonIn('Undo'));
}));

test('Opus in a polish preview re-polishes with the hard profile', withPolish(async () => {
  const { dialog, calls, reply, note, buttonIn } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  await reply(polished('Polished'));
  buttonIn('Opus').click();
  assert.match(note().textContent, /Polishing with Opus/);
  assert.deepEqual(calls[1], { type: 'polish', text: ENGLISH, profile: 'hard' });
  await reply(polished('Polished harder', 'claude-opus-5-5'));
  assert.equal(userText(dialog), 'Polished harder');
  assert.match(note().textContent, /Opus/);
  assert.equal(note().querySelector('select'), null);
  undo(dialog);
  assert.equal(userText(dialog), ENGLISH);
}));

test('Korean typed over a polish preview starts a translation', withPolish(async () => {
  const { dialog, calls, reply, note } = setup();
  draft(dialog, ENGLISH);
  translate(dialog);
  await reply(polished('Polished'));
  draft(dialog, '새 초안');
  translate(dialog);
  assert.equal(calls[1].type, 'email');
  assert.equal(calls[1].korean, '새 초안');
  await reply(ok('New draft'));
  assert.ok(note().querySelector('select')); // back to a translate preview
}));

test('Esc undoes a preview and cancels a translation in flight', async () => {
  const { inline, reply, note } = setup();
  assert.equal(escape(inline), false); // idle: Gmail keeps the key
  translate(inline);
  await reply(ok('First'));
  assert.equal(escape(inline), true);
  assert.equal(userText(inline), KOREAN);
  assert.equal(note(), null);
  translate(inline);
  assert.equal(escape(inline), true);
  await reply(ok('Late'));
  assert.equal(userText(inline), KOREAN);
  assert.equal(note(), null);
});

test('the preview card shows the model and the Esc hint', async () => {
  const { inline, reply, note } = setup();
  translate(inline);
  await reply(ok('First', 'claude-opus-5-5'));
  assert.equal(note().querySelector('.model').textContent, 'Opus');
  assert.equal(note().querySelector('.hints').textContent, 'Esc undo');
});

test('Esc after editing the translation keeps the edit and asks instead', async () => {
  const { inline, calls, reply, note, buttonIn } = setup();
  translate(inline);
  await reply(ok('First'));
  inline.firstChild.textContent = 'First, edited';
  assert.equal(escape(inline), true); // swallowed: the prompt answers it
  assert.equal(userText(inline), 'First, edited');
  assert.equal(calls.length, 1);
  assert.match(note().textContent, /You edited the translation/);
  buttonIn('Keep my edit').click();
  assert.equal(userText(inline), 'First, edited');
  assert.match(note().textContent, /역번역/);
  buttonIn('Undo').click();
  assert.equal(userText(inline), KOREAN); // an explicit Undo still goes back
});

test('changing the language puts focus back in the compose body', async () => {
  const { inline, calls, reply, note } = setup();
  translate(inline);
  await reply(ok('First'));
  const sel = note().querySelector('select');
  sel.focus();
  sel.value = 'ja';
  sel.dispatchEvent(new document.defaultView.Event('change'));
  assert.equal(calls[1].lang, 'ja');
  assert.equal(document.activeElement, inline);
});

test('a reloaded extension shows the stale error, not Chrome\'s message', async () => {
  for (const message of ['Could not establish connection. Receiving end does not exist.', 'Extension context invalidated.']) {
    const { inline, note } = setup();
    chrome.runtime.sendMessage = (msg) => (msg.type === 'badge'
      ? Promise.resolve({ ok: true, data: true })
      : Promise.reject(new Error(message)));
    translate(inline);
    await flush();
    assert.match(note().textContent, /protly was reloaded or updated/);
    assert.doesNotMatch(note().textContent, /Receiving end|context invalidated/);
  }
});
