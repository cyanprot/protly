import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { showToast, _resetToasts } from '../src/ui/toast.js';

let doc;
const list = () => doc.querySelector('.pl-toasts')?.shadowRoot.querySelector('.list');
const texts = () => [...(list()?.querySelectorAll('.toast .msg') || [])].map((n) => n.textContent);

beforeEach(() => {
  doc = new JSDOM('<body></body>').window.document;
  _resetToasts();
});

test('a toast shows its text and the protly label in a shadow root', () => {
  showToast('API key missing', { doc });
  assert.deepEqual(texts(), ['API key missing']);
  assert.equal(list().querySelector('.label').textContent, 'protly');
  assert.equal(doc.body.querySelectorAll('.msg').length, 0); // nothing leaks into the page DOM
});

test('a persistent toast shows once per text, even after dismissal', () => {
  showToast('once', { doc });
  showToast('once', { doc });
  assert.equal(texts().length, 1);
  list().querySelector('.toast').click();
  assert.equal(texts().length, 0);
  showToast('once', { doc });
  assert.equal(texts().length, 0);
});

test('a transient toast goes away after 4 s and may repeat', () => {
  mock.timers.enable({ apis: ['setTimeout'] });
  try {
    showToast('still loading', { doc, transient: true });
    showToast('still loading', { doc, transient: true });
    assert.equal(texts().length, 2);
    mock.timers.tick(4000);
    assert.equal(texts().length, 0);
  } finally {
    mock.timers.reset();
  }
});

test('error toasts carry the err class', () => {
  showToast('bad', { doc, error: true });
  assert.ok(list().querySelector('.toast.err'));
});
