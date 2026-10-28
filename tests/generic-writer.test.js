import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { readBox, writeBox } from '../src/generic/writer.js';

const docOf = (html) => new JSDOM(`<body>${html}</body>`).window.document;

test('textarea: replaces everything and fires one input event', async () => {
  const d = docOf('<textarea>안녕</textarea>');
  const el = d.querySelector('textarea');
  const events = [];
  el.addEventListener('input', (e) => events.push(e.inputType));
  assert.equal(await writeBox({ el, doc: d, kind: 'text' }, 'hi there'), true);
  assert.equal(el.value, 'hi there');
  assert.equal(readBox({ el, doc: d, kind: 'text' }), 'hi there');
  assert.deepEqual(events, ['insertReplacementText']);
});

test('input type text and email (no setRangeText on email)', async () => {
  const d = docOf('<input value="a"><input type="email" value="b">');
  const [text, email] = d.querySelectorAll('input');
  assert.equal(await writeBox({ el: text, doc: d, kind: 'text' }, 'x'), true);
  assert.equal(text.value, 'x');
  assert.equal(await writeBox({ el: email, doc: d, kind: 'text' }, 'me@example.com'), true);
  assert.equal(email.value, 'me@example.com');
});

test('contenteditable: select all, then execCommand insertText', async () => {
  const d = docOf('<div contenteditable="true">안녕<br>둘째</div>');
  const el = d.querySelector('div');
  const calls = [];
  d.execCommand = (cmd, ui, text) => { calls.push([cmd, d.getSelection().toString()]); el.textContent = text; return true; };
  assert.equal(await writeBox({ el, doc: d, kind: 'contenteditable' }, 'hello', { settleMs: 0 }), true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'insertText');
  assert.equal(el.textContent, 'hello');
});

test('contenteditable: a dropped insert reports false', async () => {
  const d = docOf('<div contenteditable="true">안녕</div>');
  const el = d.querySelector('div');
  d.execCommand = () => false; // the editor ignored it
  assert.equal(await writeBox({ el, doc: d, kind: 'contenteditable' }, 'hello', { settleMs: 0 }), false);
  assert.equal(el.textContent, '안녕');
});

test('a detached box reports false', async () => {
  const d = docOf('<textarea></textarea>');
  const el = d.querySelector('textarea');
  el.remove();
  assert.equal(await writeBox({ el, doc: d, kind: 'text' }, 'x'), false);
});

test('readBox: <p> blocks join with one newline, <br> is a newline, an empty <p> is a blank line', () => {
  const d = docOf('<div contenteditable="true"><p>하나</p><p>둘<br>셋</p><p><br></p><p>넷</p></div><div contenteditable="true">안녕<br>둘째<br></div>');
  const [p, br] = d.querySelectorAll('[contenteditable]');
  assert.equal(readBox({ el: p, doc: d, kind: 'contenteditable' }), '하나\n둘\n셋\n\n넷');
  assert.equal(readBox({ el: br, doc: d, kind: 'contenteditable' }), '안녕\n둘째');
});

test('contenteditable: an editor that renders the insert a tick later still verifies', async () => {
  const d = docOf('<div contenteditable="true">안녕</div>');
  const el = d.querySelector('div');
  d.execCommand = (cmd, ui, text) => { setTimeout(() => { el.textContent = text; }, 50); return true; };
  assert.equal(await writeBox({ el, doc: d, kind: 'contenteditable' }, 'hello', { settleMs: 0 }), true);
});

test('stillOk false right before the write: nothing is written, null', async () => {
  const d = docOf('<div contenteditable="true">안녕</div><textarea>가</textarea>');
  const el = d.querySelector('div');
  let calls = 0;
  d.execCommand = () => { calls++; return true; };
  let ok = true;
  const p = writeBox({ el, doc: d, kind: 'contenteditable' }, 'hello', { settleMs: 20, stillOk: () => ok });
  ok = false; // e.g. Esc during the select settle
  assert.equal(await p, null);
  assert.equal(calls, 0);
  const ta = d.querySelector('textarea');
  assert.equal(await writeBox({ el: ta, doc: d, kind: 'text' }, 'x', { stillOk: () => false }), null);
  assert.equal(ta.value, '가');
});

test('textarea: written without taking focus', async () => {
  const d = docOf('<textarea>안녕</textarea><input id="o">');
  const el = d.querySelector('textarea');
  d.getElementById('o').focus();
  assert.equal(await writeBox({ el, doc: d, kind: 'text' }, 'hi'), true);
  assert.equal(d.activeElement, d.getElementById('o'));
});
