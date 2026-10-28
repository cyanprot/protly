import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { createCard, modelLabel } from '../src/ui/card.js';

let win;
let doc;
beforeEach(() => {
  win = new JSDOM('<body><div id="row"></div><div id="box"></div></body>').window;
  doc = win.document;
});
const rootOf = (card) => card.host.shadowRoot.querySelector('.pl-root');
const buttons = (card) => [...rootOf(card).querySelectorAll('button')].map((b) => b.textContent);

test('modelLabel', () => {
  assert.equal(modelLabel('claude-opus-5-5'), 'Opus');
  assert.equal(modelLabel('claude-sonnet-5-5'), 'Sonnet');
  assert.equal(modelLabel(undefined), 'Sonnet');
});

test('before: inserted in flow before the anchor; hide removes it; a later call re-inserts it', () => {
  const row = doc.getElementById('row');
  const card = createCard({ doc, place: { before: row } });
  assert.equal(card.isOpen(), false);
  card.message('hello');
  assert.equal(row.previousElementSibling, card.host);
  assert.equal(card.host.className, 'pl-card');
  card.hide();
  assert.equal(card.isOpen(), false);
  card.message('again');
  assert.equal(row.previousElementSibling, card.host);
});

test('after: inserted after the element', () => {
  const box = doc.getElementById('box');
  const card = createCard({ doc, place: { after: box } });
  card.message('x');
  assert.equal(box.nextElementSibling, card.host);
});

test('working shows text and Cancel only when onCancel is given', () => {
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  card.working('Translating');
  assert.equal(rootOf(card).querySelector('.msg').textContent, 'Translating');
  assert.ok(rootOf(card).querySelector('.msg.dots'));
  assert.deepEqual(buttons(card), []);
  let cancelled = 0;
  card.working('Translating', { onCancel: () => cancelled++ });
  rootOf(card).querySelector('button').click();
  assert.equal(cancelled, 1);
});

test('preview: text, model label, chip, actions and hints', () => {
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  const picked = [];
  let undone = 0;
  card.preview({
    text: '역번역', model: 'claude-opus-5-5', lang: 'ru', onLang: (l) => picked.push(l),
    actions: [{ label: 'Undo', onClick: () => undone++ }], hints: 'Esc undo',
  });
  const r = rootOf(card);
  assert.equal(r.querySelector('.msg').textContent, '역번역');
  assert.equal(r.querySelector('.model').textContent, 'Opus');
  assert.equal(r.querySelector('.hints').textContent, 'Esc undo');
  const sel = r.querySelector('select.pl-chip');
  assert.equal(sel.value, 'ru');
  assert.equal([...sel.options].some((o) => o.value === 'ko'), false);
  sel.value = 'ja';
  sel.dispatchEvent(new win.Event('change'));
  assert.deepEqual(picked, ['ja']);
  r.querySelector('button').click();
  assert.equal(undone, 1);
});

test('preview without onLang has no chip; an unknown lang is still selectable', () => {
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  card.preview({ text: 'notes', model: 'claude-sonnet-5-5' });
  assert.equal(rootOf(card).querySelector('select'), null);
  card.preview({ text: 't', lang: 'xx', onLang: () => {} });
  assert.equal(rootOf(card).querySelector('select').value, 'xx');
});

test('message: error class, actions, optional chip', () => {
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  card.message('Failed', { error: true, actions: [{ label: 'Opus', onClick() {} }], lang: 'en', onLang() {} });
  assert.ok(rootOf(card).classList.contains('err'));
  assert.deepEqual(buttons(card), ['Opus']);
  assert.ok(rootOf(card).querySelector('select'));
  card.message('fine');
  assert.equal(rootOf(card).classList.contains('err'), false);
});

test('float: fixed under the rect, above it when there is no room, re-placed on scroll', () => {
  let rect = { top: 100, bottom: 120, left: 30, right: 300 };
  const card = createCard({ doc, place: { float: () => rect } });
  card.host.getBoundingClientRect = () => ({ width: 200, height: 40 });
  card.message('x');
  assert.equal(card.host.parentElement, doc.body);
  assert.equal(card.host.style.position, 'fixed');
  assert.equal(card.host.style.top, '126px');
  assert.equal(card.host.style.left, '30px');
  rect = { top: 740, bottom: 760, left: 30, right: 300 }; // jsdom innerHeight is 768
  win.dispatchEvent(new win.Event('scroll'));
  assert.equal(card.host.style.top, '694px');
  card.hide();
  rect = { top: 100, bottom: 120, left: 30, right: 300 };
  win.dispatchEvent(new win.Event('scroll')); // listener gone with the card
  assert.equal(card.host.style.top, '694px');
});

test('float: a host the page removed without hide() drops its scroll and resize listeners', () => {
  let rect = { top: 100, bottom: 120, left: 30, right: 300 };
  const card = createCard({ doc, place: { float: () => rect } });
  card.host.getBoundingClientRect = () => ({ width: 200, height: 40 });
  card.message('x');
  assert.equal(card.host.style.top, '126px');
  card.host.remove();
  rect = { top: 300, bottom: 320, left: 30, right: 300 };
  win.dispatchEvent(new win.Event('scroll')); // sees the detached host and cleans up
  assert.equal(card.host.style.top, '126px');
  doc.body.appendChild(card.host); // reattached by hand, not through render: no listener left
  win.dispatchEvent(new win.Event('resize'));
  assert.equal(card.host.style.top, '126px');
  card.host.remove();
  card.message('again'); // a later render re-inserts and re-places it
  assert.equal(card.isOpen(), true);
  assert.equal(card.host.style.top, '326px');
});

test('the theme follows the page', () => {
  doc.body.style.backgroundColor = 'rgb(10, 10, 10)';
  const card = createCard({ doc, place: { before: doc.getElementById('row') } });
  card.message('x');
  assert.equal(rootOf(card).dataset.plTheme, 'dark');
});
