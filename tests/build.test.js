import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const url = new URL('../dist/generic.js', import.meta.url);

test('the generic bundle exists (npm test builds it first)', () => {
  assert.ok(existsSync(url), 'dist/generic.js missing: run npm run build');
});

test('the generic bundle loads nothing from a page context', () => {
  const src = readFileSync(url, 'utf8');
  assert.equal(src.includes('chrome.runtime.getURL'), false);
  assert.equal(/\bimport\s*\(/.test(src), false); // no dynamic imports: one self-contained IIFE
});

test('injecting the bundle twice keeps one instance', () => {
  const src = readFileSync(url, 'utf8');
  const dom = new JSDOM('<body></body>', { runScripts: 'outside-only' });
  dom.window.eval(src);
  const first = dom.window.__protly;
  assert.equal(typeof first.run, 'function');
  assert.equal(typeof first.toast, 'function');
  dom.window.eval(src);
  assert.equal(dom.window.__protly, first);
});
