import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addFonts, fetchFonts, FONT_FILES } from '../src/ui/fonts.js';

function fakeDoc() {
  const added = [];
  class FontFace {
    constructor(family, src, desc) { Object.assign(this, { family, src, desc }); }
    load() { return Promise.resolve(this); }
  }
  return { added, defaultView: { FontFace }, fonts: { add: (f) => added.push(f) } };
}

test('addFonts registers protly-mono 400 and 500 once per document', () => {
  const doc = fakeDoc();
  const bytes = new Uint8Array([1, 2, 3]);
  addFonts(doc, { regular: bytes, medium: 'chrome-extension://x/m.woff2' });
  addFonts(doc, { regular: bytes, medium: 'chrome-extension://x/m.woff2' });
  assert.equal(doc.added.length, 2);
  assert.deepEqual(doc.added.map((f) => [f.family, f.desc.weight]), [['protly-mono', '400'], ['protly-mono', '500']]);
  assert.equal(doc.added[0].src, bytes); // bytes pass through untouched
  assert.equal(doc.added[1].src, 'url("chrome-extension://x/m.woff2")');
});

test('a second document gets its own faces', () => {
  const a = fakeDoc();
  const b = fakeDoc();
  addFonts(a, { regular: 'r', medium: 'm' });
  addFonts(b, { regular: 'r', medium: 'm' });
  assert.equal(b.added.length, 2);
});

test('fetchFonts reads both files through getURL as bytes', async () => {
  const seen = [];
  const fetchImpl = async (url) => { seen.push(url); return { ok: true, arrayBuffer: async () => new ArrayBuffer(4) }; };
  const f = await fetchFonts((p) => `ext://${p}`, fetchImpl);
  assert.deepEqual(seen, [`ext://${FONT_FILES.regular}`, `ext://${FONT_FILES.medium}`]);
  assert.equal(f.regular.byteLength, 4);
  assert.equal(f.medium.byteLength, 4);
});

test('fetchFonts rejects on a missing file', async () => {
  const fetchImpl = async () => ({ ok: false, status: 404 });
  await assert.rejects(fetchFonts((p) => p, fetchImpl), /404/);
});
