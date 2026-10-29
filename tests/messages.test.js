import { test } from 'node:test';
import assert from 'node:assert/strict';
import { senderClass, allowed, SENDERS, PAGE } from '../src/lib/messages.js';

const ID = 'abcdefghijklmnopabcdefghijklmnop';

test('senderClass: extension pages, content-script origins, and everything else', () => {
  assert.equal(senderClass({ id: ID, url: `chrome-extension://${ID}/popup/popup.html` }, ID), PAGE);
  assert.equal(senderClass({ id: ID, url: `chrome-extension://${ID}/options/options.html`, tab: { id: 4 } }, ID), PAGE);
  // No sender.origin (older Chrome): fall back to the URL's origin.
  assert.equal(senderClass({ id: ID, url: 'https://www.instagram.com/direct/t/1/', tab: { id: 1 } }, ID), 'https://www.instagram.com');
  assert.equal(senderClass({ id: ID, url: 'https://a.example/', origin: 'https://a.example', tab: { id: 1 } }, ID), 'https://a.example');
  for (const s of [
    null, undefined, {}, { id: 'x'.repeat(32), url: 'https://a.example/', tab: { id: 1 } },
    { id: ID, url: 'https://a.example/' }, // no tab
    { id: ID, url: 'not a url', tab: { id: 1 } },
    { id: ID, url: 'https://a.example/', origin: 'null', tab: { id: 1 } }, // sandboxed frame
    { id: ID, url: 'file:///etc/passwd', tab: { id: 1 } },
    { id: ID, url: `chrome-extension://${'x'.repeat(32)}/a.html`, tab: { id: 1 } },
  ]) assert.equal(senderClass(s, ID), null, JSON.stringify(s));
  assert.equal(senderClass({ id: undefined, url: 'chrome-extension://undefined/x' }, undefined), null);
});

test('allowed: default deny for unlisted and inherited names', () => {
  const s = { id: ID, url: `chrome-extension://${ID}/popup/popup.html` };
  assert.equal(allowed('diag', s, ID), true);
  for (const type of ['nope', 'constructor', '__proto__', 'toString']) assert.equal(allowed(type, s, ID), false, type);
  assert.ok(Object.values(SENDERS).every((l) => Array.isArray(l) && l.length > 0));
});

test('checkShape accepts what the adapters send: every picker language, both context shapes, null langs', async () => {
  const { checkShape } = await import('../src/lib/messages.js');
  const { LANG_NAMES } = await import('../src/lib/lang.js');
  for (const code of ['auto', ...Object.keys(LANG_NAMES)]) {
    checkShape('setThread', { threadId: '340282366920938463463374607431768211455', patch: { outputLang: code } });
  }
  for (const code of Object.keys(LANG_NAMES)) checkShape('box', { text: '안녕', lang: code, profile: 'hard', hostname: 'xn--9n2bp8q.example' });
  checkShape('box', { text: '안녕', lang: null, profile: 'outgoing', hostname: '' });
  checkShape('email', { context: [{ from: 'me', text: 'a' }, { from: 'them', text: 'b' }], korean: '안녕', profile: 'hard', lang: 'auto' });
  checkShape('outgoing', { threadId: 'abc', context: [{ from: 'partner', text: '' }], korean: '안녕', profile: 'outgoing', lang: null });
  checkShape('sent', { threadId: 'abc', text: 'hi', korean: null });
  checkShape('tabStatus', {});
  assert.throws(() => checkShape('nope', {}), (e) => e.kind === 'bad_message');
  assert.throws(() => checkShape('getThread', { threadId: 'a b' }), (e) => e.kind === 'bad_message' && /threadId/.test(e.message));
});
