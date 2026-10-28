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

test('an indented paragraph (bare blockquote) is part of the user text', () => {
  const doc = new JSDOM('<body><div id="b">위<blockquote style="margin:0 0 0 40px">들여쓴 문단</blockquote><div class="gmail_quote">old</div></div></body>').window.document;
  assert.equal(nodesToText(userNodes(doc.getElementById('b'))), '위\n들여쓴 문단');
});

test('a wrapper div around text and signature is descended into', () => {
  const doc = new JSDOM('<body><div id="b"><div dir="ltr">안녕<div>둘째</div><br><div class="gmail_signature">Sig</div></div></div></body>').window.document;
  const body = doc.getElementById('b');
  assert.equal(nodesToText(userNodes(body)), '안녕\n둘째');
  replaceUserNodes(body, textToNodes(doc, 'Hi'));
  assert.equal(nodesToText(userNodes(body)), 'Hi');
  assert.ok(body.querySelector('[dir="ltr"] > .gmail_signature'));
});
