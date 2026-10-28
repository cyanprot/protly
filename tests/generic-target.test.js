import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { classify, deepActive, findTarget, selectionInfo } from '../src/generic/target.js';

const docOf = (html) => new JSDOM(`<body>${html}</body>`).window.document;

test('classify: textareas and text-like inputs are text boxes', () => {
  const d = docOf(`<textarea></textarea><input><input type="search"><input type="email"><input type="url">
    <input type="tel"><input type="text" readonly><input type="password"><input type="checkbox"><textarea disabled></textarea>`);
  const kinds = [...d.querySelectorAll('textarea, input')].map(classify);
  assert.deepEqual(kinds, ['text', 'text', 'text', 'text', 'text', 'text', null, null, null, null]);
});

test('classify: contenteditable and its children; contenteditable=false is not', () => {
  const d = docOf('<div id="r" contenteditable="true"><p id="c">x</p><span id="n" contenteditable="false">y</span></div><div id="plain">z</div>');
  assert.equal(classify(d.getElementById('r')), 'contenteditable');
  assert.equal(classify(d.getElementById('c')), 'contenteditable');
  assert.equal(classify(d.getElementById('n')), null);
  assert.equal(classify(d.getElementById('plain')), null);
  assert.equal(classify(null), null);
});

test('findTarget: focused textarea; contenteditable resolves to its root', () => {
  const d = docOf('<textarea id="t"></textarea><div id="r" contenteditable="true" tabindex="0"><p id="c" tabindex="0">x</p></div>');
  d.getElementById('t').focus();
  assert.deepEqual(findTarget(d), { el: d.getElementById('t'), doc: d, kind: 'text' });
  d.getElementById('c').focus();
  assert.equal(findTarget(d).el, d.getElementById('r'));
  d.activeElement.blur();
  assert.equal(findTarget(d), null);
});

test('deepActive follows same-origin iframes and stops at cross-origin ones', () => {
  const inner = docOf('<textarea id="t"></textarea>');
  inner.getElementById('t').focus();
  const sameOrigin = { activeElement: { tagName: 'IFRAME', contentDocument: inner } };
  assert.equal(deepActive(sameOrigin).el, inner.getElementById('t'));
  assert.equal(deepActive(sameOrigin).doc, inner);
  const crossNull = { activeElement: { tagName: 'IFRAME', contentDocument: null } };
  assert.equal(deepActive(crossNull).el, null);
  const crossThrows = { activeElement: { tagName: 'IFRAME', get contentDocument() { throw new Error('SecurityError'); } } };
  assert.equal(deepActive(crossThrows).el, null);
});

test('selectionInfo returns the selected text and its document', () => {
  const d = docOf('<p id="p">hello world</p>');
  const r = d.createRange();
  r.selectNodeContents(d.getElementById('p'));
  d.getSelection().addRange(r);
  const s = selectionInfo(d);
  assert.equal(s.text, 'hello world');
  assert.equal(s.doc, d);
  assert.equal(typeof s.rect, 'function');
  assert.equal(selectionInfo(docOf('<p>x</p>')).text, '');
});
