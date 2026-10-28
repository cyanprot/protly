import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { readMessages, findThreadRoot } from '../src/content/dom.js';
import { findViewerName } from '../src/content/selectors.js';

const html = readFileSync(new URL('./fixtures/thread.html', import.meta.url), 'utf8');
const doc = new JSDOM(`<body>${html}</body>`).window.document;

const EXPECTED_ROWS = 7; // text rows msg 13, 17, 21, 25, 29, 33, 37 (docs/spike-notes.md)
const EXPECTED_SENDERS = ['partner', 'partner', 'partner', 'partner', 'partner', 'me', 'me'];
const VIEWER = 'viewer_user'; // the snapshot holds only main, so the viewer is passed in

test('finds thread root', () => {
  assert.ok(findThreadRoot(doc));
});

test('reads text rows with sender, in order', () => {
  const msgs = readMessages(findThreadRoot(doc), VIEWER);
  assert.equal(msgs.length, EXPECTED_ROWS);
  assert.deepEqual(msgs.map((m) => m.from), EXPECTED_SENDERS);
  for (const m of msgs) assert.match(m.text, /^msg \d+/);
});

test('findViewerName reads the sidebar profile link, ignores avatars inside main', () => {
  const d = new JSDOM(`<body>
    <div role="main"><a href="/x/"><img alt="partner_user's profile picture"></a></div>
    <nav><a href="/viewer_user/"><img alt="viewer_user's profile picture"></a></nav>
  </body>`).window.document;
  assert.equal(findViewerName(d), 'viewer_user');
  assert.equal(findViewerName(new JSDOM('<body></body>').window.document), null);
});

import { renderTranslation, clearTranslation, setHoverOriginal } from '../src/content/dom.js';

function bubble() {
  const d = new JSDOM('<div class="row"><span class="t">привет</span></div>').window.document;
  return { row: d.querySelector('.row'), textEl: d.querySelector('.t') };
}

test('below mode adds a sibling, keeps original visible', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'below');
  assert.equal(m.row.querySelector('.pl-tr').textContent, 'hi');
  assert.equal(m.textEl.hasAttribute('data-pl-hide'), false);
});

test('replace mode hides original, shows translation with original on hover', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'replace');
  assert.equal(m.textEl.getAttribute('data-pl-hide'), '');
  const tr = m.row.querySelector('.pl-tr');
  assert.equal(tr.textContent, 'hi');
  assert.equal(tr.title, 'привет');
});

test('render is idempotent and clear restores', () => {
  const m = bubble();
  renderTranslation(m, 'hi', 'replace');
  renderTranslation(m, 'hello', 'below');
  assert.equal(m.row.querySelectorAll('.pl-tr').length, 1);
  assert.equal(m.textEl.hasAttribute('data-pl-hide'), false);
  clearTranslation(m);
  assert.equal(m.row.querySelectorAll('.pl-tr').length, 0);
});

test('setHoverOriginal sets title on own bubble', () => {
  const m = bubble();
  setHoverOriginal(m, '안녕');
  assert.equal(m.textEl.title, '안녕');
});

test('clearAllTranslations removes everything we added, including hover titles', async () => {
  const { clearAllTranslations, setHoverOriginal, renderTranslation, stillShows } = await import('../src/content/dom.js');
  const d = new JSDOM('<body><div role="main"><div><div dir="auto">hello</div></div><div><div dir="auto">mine</div></div></div></body>').window.document;
  const [a, b] = d.querySelectorAll('div[dir="auto"]');
  renderTranslation({ textEl: a, text: 'hello' }, '안녕', 'replace');
  setHoverOriginal({ textEl: b, text: 'mine' }, '내 원문');
  assert.ok(stillShows({ textEl: a, text: 'hello' }));
  clearAllTranslations(d.querySelector('[role="main"]'));
  assert.equal(d.querySelectorAll('.pl-tr').length, 0);
  assert.equal(a.hasAttribute('data-pl-hide'), false);
  assert.equal(b.hasAttribute('title'), false);
  a.textContent = 'other message';
  assert.equal(stillShows({ textEl: a, text: 'hello' }), false);
});
