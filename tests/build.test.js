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

// The instance lives under a registered symbol: no element id or name can reach it through window's named access.
const KEY = Symbol.for('protly');

test('injecting the bundle twice keeps one instance', () => {
  const src = readFileSync(url, 'utf8');
  const dom = new JSDOM('<body></body>', { runScripts: 'outside-only' });
  dom.window.eval(src);
  const first = dom.window[KEY];
  assert.equal(typeof first?.run, 'function');
  assert.equal(typeof first.toast, 'function');
  dom.window.eval(src);
  assert.equal(dom.window[KEY], first);
});

test('a page element named __protly cannot stand in for the instance', () => {
  const src = readFileSync(url, 'utf8');
  for (const html of ['<div id="__protly"></div>', '<form name="__protly"></form>', '<img name="__protly">',
    '<form id="__protly"><object name="run"></object><object name="toast"></object></form>']) {
    const dom = new JSDOM(`<body>${html}</body>`, { runScripts: 'outside-only' });
    const named = dom.window.__protly;
    assert.ok(named, 'named access holds the element first');
    dom.window.eval(src);
    assert.equal(typeof dom.window[KEY]?.run, 'function', html);
    assert.equal(typeof dom.window[KEY].toast, 'function', html);
    assert.equal(dom.window.__protly, named, html); // the old string key is left to the page
  }
});
