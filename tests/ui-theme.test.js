import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { parseColor, luminance, pickTheme, bindTheme } from '../src/ui/theme.js';
import { TOKENS, BASE } from '../src/ui/tokens.css.js';

const tick = () => new Promise((r) => setTimeout(r, 0));
const page = (bodyStyle = '', htmlStyle = '') =>
  new JSDOM(`<html style="${htmlStyle}"><body style="${bodyStyle}"></body></html>`).window.document;

test('parseColor reads rgb and rgba, rejects the rest', () => {
  assert.deepEqual(parseColor('rgb(20, 30, 40)'), [20, 30, 40, 1]);
  assert.deepEqual(parseColor('rgba(0, 0, 0, 0)'), [0, 0, 0, 0]);
  assert.deepEqual(parseColor('rgb(1 2 3 / 50%)'), [1, 2, 3, 0.5]);
  assert.equal(parseColor('transparent'), null);
  assert.equal(parseColor(''), null);
});

test('luminance follows WCAG', () => {
  assert.equal(luminance([0, 0, 0]), 0);
  assert.equal(luminance([255, 255, 255]), 1);
  assert.ok(Math.abs(luminance([245, 240, 230]) - 0.87) < 0.02);
});

test('pickTheme: dark body, light body, transparent falls back to html, then light', () => {
  assert.equal(pickTheme(page('background-color: rgb(18, 18, 18)')), 'dark');
  assert.equal(pickTheme(page('background-color: rgb(250, 250, 250)')), 'light');
  assert.equal(pickTheme(page('', 'background-color: rgb(0, 0, 0)')), 'dark');
  assert.equal(pickTheme(page()), 'light');
});

test('bindTheme sets data-pl-theme and follows body style changes until unbound', async () => {
  const doc = page('background-color: rgb(250, 250, 250)');
  const el = doc.body.appendChild(doc.createElement('div'));
  const unbind = bindTheme(el, doc);
  assert.equal(el.dataset.plTheme, 'light');
  doc.body.style.backgroundColor = 'rgb(10, 10, 10)';
  await tick();
  assert.equal(el.dataset.plTheme, 'dark');
  unbind();
  doc.body.style.backgroundColor = 'rgb(250, 250, 250)';
  await tick();
  assert.equal(el.dataset.plTheme, 'dark');
});

test('bindTheme drops an element the page detached without unbinding', async () => {
  const doc = page('background-color: rgb(250, 250, 250)');
  const el = doc.body.appendChild(doc.createElement('div'));
  const kept = doc.body.appendChild(doc.createElement('div'));
  bindTheme(el, doc);
  bindTheme(kept, doc);
  el.remove(); // e.g. Gmail closing a compose window without hide()
  doc.body.style.backgroundColor = 'rgb(10, 10, 10)';
  await tick();
  assert.equal(el.dataset.plTheme, 'light');
  assert.equal(kept.dataset.plTheme, 'dark');
  doc.body.appendChild(el); // back in the page but never re-bound: it was dropped, not just skipped
  doc.body.style.backgroundColor = 'rgb(250, 250, 250)';
  await tick();
  assert.equal(el.dataset.plTheme, 'light');
  assert.equal(kept.dataset.plTheme, 'light');
  doc.body.style.backgroundColor = 'rgb(10, 10, 10)';
  await tick();
  assert.equal(el.dataset.plTheme, 'light');
  assert.equal(kept.dataset.plTheme, 'dark');
});

test('tokens define paper, ink and a dark swap, with no shadows or gradients', () => {
  assert.match(TOKENS, /--pl-paper: #F5F0E6/);
  assert.match(TOKENS, /--pl-ink: #1A1F2E/);
  assert.match(TOKENS, /\[data-pl-theme=dark\]/);
  assert.doesNotMatch(TOKENS + BASE, /shadow|gradient/);
});
