import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBadgeStore } from '../src/lib/badge.js';

// chrome.storage.session stand-in.
function memSession() {
  const data = {};
  return {
    data,
    get: async (k) => (k in data ? { [k]: data[k] } : {}),
    set: async (o) => { Object.assign(data, o); },
    remove: async (k) => { delete data[k]; },
  };
}

test('set stores text and reason under badge:<tabId>', async () => {
  const s = memSession();
  const b = createBadgeStore(s);
  await b.set(7, { text: '!', reason: 'Gmail Send button not found' });
  assert.deepEqual(s.data, { 'badge:7': { text: '!', reason: 'Gmail Send button not found' } });
  assert.deepEqual(await b.get(7), { text: '!', reason: 'Gmail Send button not found' });
});

test('empty text clears; clear() clears; get of nothing is null', async () => {
  const s = memSession();
  const b = createBadgeStore(s);
  await b.set(7, { text: '!', reason: 'x' });
  await b.set(7, { text: '' });
  assert.equal(await b.get(7), null);
  await b.set(8, { text: '!' });
  assert.deepEqual(await b.get(8), { text: '!', reason: '' });
  await b.clear(8);
  assert.equal(await b.get(8), null);
});

test('a message without a tab is ignored', async () => {
  const s = memSession();
  await createBadgeStore(s).set(undefined, { text: '!', reason: 'x' });
  assert.deepEqual(s.data, {});
});
