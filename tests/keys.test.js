import { test } from 'node:test';
import assert from 'node:assert/strict';
import { threadIdFromPath, threadKey, cacheKey, sentKey, expiredKeys, PRUNE_MS, withThreadDefaults } from '../src/lib/keys.js';

test('threadIdFromPath', () => {
  assert.equal(threadIdFromPath('/direct/t/1234567/'), '1234567');
  assert.equal(threadIdFromPath('/direct/t/abc'), 'abc');
  assert.equal(threadIdFromPath('/direct/inbox/'), null);
  assert.equal(threadIdFromPath('/'), null);
});

test('threadKey', () => assert.equal(threadKey('42'), 't:42'));

test('cacheKey is stable and depends on every part', async () => {
  const a = await cacheKey('t1', 'hi', 'ko');
  assert.match(a, /^c:[0-9a-f]{64}$/);
  assert.equal(a, await cacheKey('t1', 'hi', 'ko'));
  assert.notEqual(a, await cacheKey('t2', 'hi', 'ko'));
  assert.notEqual(a, await cacheKey('t1', 'hi', 'en'));
  assert.notEqual(a, await cacheKey('t1', 'hi!', 'ko'));
});

test('sentKey', async () => {
  const a = await sentKey('t1', 'see you');
  assert.match(a, /^s:[0-9a-f]{64}$/);
  assert.notEqual(a, await sentKey('t1', 'see you!'));
});

test('sentKey ignores whitespace differences', async () => {
  assert.equal(await sentKey('t1', ' see  you\n'), await sentKey('t1', 'see you'));
});

test('expiredKeys only prunes old c: and s: entries', () => {
  const now = 1_000_000_000_000;
  const all = {
    settings: { ts: 0 },
    't:1': { ts: 0 },
    'c:old': { ts: now - PRUNE_MS - 1 },
    'c:new': { ts: now - 1000 },
    's:old': { ts: now - PRUNE_MS - 1 },
    'c:bad': {},
  };
  assert.deepEqual(expiredKeys(all, now).sort(), ['c:old', 's:old']);
});

test('withThreadDefaults fills missing fields from settings defaults', () => {
  const t = withThreadDefaults({ memo: 'bro' }, { otherTarget: 'en', pastMode: 'below', newMode: 'below' });
  assert.equal(t.memo, 'bro');
  assert.equal(t.otherTarget, 'en');
  assert.equal(t.outputLang, 'auto');
  assert.equal(t.enabled, true);
  assert.equal(t.partnerLang, null);
});
