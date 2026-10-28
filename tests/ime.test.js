import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { commitByRefocus, settleComposition } from '../src/lib/ime.js';

function page(html) {
  const doc = new JSDOM(`<body>${html}</body>`).window.document;
  return { doc, el: doc.body.firstElementChild };
}

test('commitByRefocus blurs, refocuses and keeps the textarea caret', () => {
  const { doc, el } = page('<textarea>안녕하세요</textarea>');
  el.focus();
  el.setSelectionRange(2, 4);
  const seen = [];
  el.addEventListener('blur', () => seen.push('blur'));
  el.addEventListener('focus', () => seen.push('focus'));
  commitByRefocus(el);
  assert.deepEqual(seen, ['blur', 'focus']);
  assert.equal(doc.activeElement, el);
  assert.deepEqual([el.selectionStart, el.selectionEnd], [2, 4]);
});

test('commitByRefocus keeps a contenteditable range', () => {
  const { doc, el } = page('<div contenteditable="true" tabindex="0">hello world</div>');
  el.focus();
  const r = doc.createRange();
  r.setStart(el.firstChild, 6);
  r.setEnd(el.firstChild, 11);
  doc.getSelection().removeAllRanges();
  doc.getSelection().addRange(r);
  commitByRefocus(el);
  assert.equal(doc.getSelection().toString(), 'world');
});

test('settleComposition resolves at once when nothing is composing', async () => {
  const { el } = page('<textarea></textarea>');
  let blurred = false;
  el.addEventListener('blur', () => { blurred = true; });
  const t0 = Date.now();
  await settleComposition(el, { composing: false });
  assert.ok(Date.now() - t0 < 200);
  assert.equal(blurred, false);
});

test('settleComposition waits for compositionend and does not refocus', async () => {
  const { doc, el } = page('<textarea></textarea>');
  el.focus();
  let blurred = false;
  el.addEventListener('blur', () => { blurred = true; });
  const p = settleComposition(el, { composing: true, timeoutMs: 1000 });
  setTimeout(() => el.dispatchEvent(new doc.defaultView.CompositionEvent('compositionend', { bubbles: true })), 10);
  const t0 = Date.now();
  await p;
  assert.ok(Date.now() - t0 < 500);
  assert.equal(blurred, false);
});

test('settleComposition commits by refocus on timeout', async () => {
  const { el } = page('<textarea></textarea>');
  el.focus();
  let blurred = false;
  el.addEventListener('blur', () => { blurred = true; });
  await settleComposition(el, { composing: true, timeoutMs: 20 });
  assert.equal(blurred, true);
});
