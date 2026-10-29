// Drives the real src/background.js message listener through a fake chrome (tests/fake-chrome.js).
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { installFakeChrome, senders, NO_RESPONSE, apiReply } from './fake-chrome.js';

const fake = installFakeChrome();
await import('../src/background.js');
const { send, local, native } = fake;

beforeEach(() => {
  local.reset();
  fake.session.reset();
  native.sent.length = 0;
  // Every request gets an answer, so a command that should have been refused fails its test instead of hanging.
  native.replyWith = (m) => (m.ping ? { ping: { ok: true } } : { status: 400, retry_after: null, body: { error: { message: 'unexpected call' } } });
  fake.badges.length = 0;
});

test('a documented command still works from its sender', async () => {
  const r = await send({ type: 'getThread', threadId: '123' }, senders.instagram);
  assert.equal(r.ok, true);
  assert.equal(r.data.enabled, true);
});

test('inherited object names are not commands', async () => {
  for (const type of ['constructor', 'toString', 'valueOf', 'hasOwnProperty', '__proto__', '__defineGetter__', 'isPrototypeOf']) {
    const r = await send({ type, threadId: '1' }, senders.instagram);
    assert.equal(r, NO_RESPONSE, type);
  }
  for (const msg of [null, undefined, 'getThread', 42, [], { type: 7 }, { type: ['getThread'] }]) {
    assert.equal(await send(msg, senders.instagram), NO_RESPONSE, JSON.stringify(msg));
  }
  assert.equal(native.sent.length, 0);
});

// What each sender may call. Everything else is refused before a handler runs.
const PAGE_ONLY = ['tabStatus', 'diag', 'testCall', 'usageSummary'];
const INSTAGRAM_ONLY = ['getThread', 'setThread', 'incoming', 'outgoing', 'suggestMemo', 'sent', 'lookupSent'];
const ALL = [...PAGE_ONLY, ...INSTAGRAM_ONLY, 'email', 'polish', 'box', 'selection', 'badge'];
const refused = (r) => r !== NO_RESPONSE && r.ok === false && r.error.kind === 'forbidden';

test('content scripts cannot call the popup and options commands', async () => {
  native.replyWith = (m) => (m.ping ? { ping: { ok: true } } : apiReply({}));
  for (const s of ['instagram', 'gmail', 'page']) {
    for (const type of PAGE_ONLY) assert.ok(refused(await send({ type }, senders[s])), `${type} from ${s}`);
  }
  assert.equal(native.sent.length, 0); // no billed testCall, no ping
});

test('thread commands come only from the Instagram content script', async () => {
  native.replyWith = () => apiReply({ items: [], translation: 'x', back_translation: 'y', memo: 'm' });
  for (const s of ['gmail', 'page', 'popup', 'options']) {
    for (const type of INSTAGRAM_ONLY) {
      assert.ok(refused(await send({ type, threadId: '1', patch: { memo: 'x' }, context: [], items: [], texts: [], text: 'a', korean: 'a' }, senders[s])), `${type} from ${s}`);
    }
  }
  assert.deepEqual(local.dump(), {}); // nothing written
  assert.equal(native.sent.length, 0);
});

test('email comes only from Gmail, badge only from the two site adapters', async () => {
  for (const s of ['instagram', 'page', 'popup', 'options']) {
    assert.ok(refused(await send({ type: 'email', context: [], korean: '안녕', profile: 'email', lang: 'auto' }, senders[s])), s);
  }
  for (const s of ['page', 'popup', 'options']) {
    assert.ok(refused(await send({ type: 'badge', text: '!', reason: 'x' }, senders[s])), s);
  }
  assert.deepEqual(fake.badges, []);
  assert.equal(native.sent.length, 0);
});

test('the any-site commands are refused to extension pages and to other extensions', async () => {
  for (const type of ['polish', 'box', 'selection']) {
    assert.ok(refused(await send({ type, text: 'hello' }, senders.popup)), type);
  }
  for (const type of ALL) assert.ok(refused(await send({ type }, senders.otherExtension)), type);
  for (const sender of [undefined, {}, { id: senders.page.id }, { ...senders.page, tab: undefined }]) {
    assert.ok(refused(await send({ type: 'polish', text: 'hello' }, sender)), JSON.stringify(sender));
  }
  assert.equal(native.sent.length, 0);
});

test('each documented sender reaches its commands', async () => {
  native.replyWith = (m) => (m.ping ? { ping: { ok: true, key_present: true, workspace_header: false } }
    : apiReply({ translation: 'hi', back_translation: '안녕', lang: 'en', items: [{ id: '0', src_lang: 'en', translation: '안녕' }] }));
  const ok = async (msg, s) => { const r = await send(msg, senders[s]); assert.equal(r.ok, true, `${msg.type} from ${s}: ${JSON.stringify(r)}`); return r.data; };
  await ok({ type: 'usageSummary' }, 'popup');
  await ok({ type: 'tabStatus', tabId: 1, url: 'https://www.instagram.com/' }, 'popup');
  await ok({ type: 'diag' }, 'options');
  await ok({ type: 'testCall' }, 'options');
  await ok({ type: 'polish', text: 'hello', profile: 'polish' }, 'page');
  await ok({ type: 'box', text: '안녕', lang: 'en', profile: 'outgoing', hostname: 'evil.example' }, 'page');
  await ok({ type: 'selection', text: 'hello' }, 'page');
  await ok({ type: 'polish', text: 'hello', profile: 'email' }, 'gmail');
  await ok({ type: 'email', context: [], korean: '안녕', profile: 'email', lang: 'auto' }, 'gmail');
  await ok({ type: 'badge', text: '!', reason: 'Gmail Send button not found' }, 'gmail');
  await ok({ type: 'outgoing', threadId: '1', context: [], korean: '안녕', profile: 'outgoing', lang: null }, 'instagram');
  await ok({ type: 'incoming', threadId: '1', context: [], items: [{ id: '0', text: 'hi', from: 'partner' }], updateLang: true }, 'instagram');
  await ok({ type: 'setThread', threadId: '1', patch: { memo: 'old friend' } }, 'instagram');
  await ok({ type: 'sent', threadId: '1', text: 'hi', korean: '안녕' }, 'instagram');
  assert.deepEqual(await ok({ type: 'lookupSent', threadId: '1', texts: ['hi'] }, 'instagram'), { hi: '안녕' });
  await ok({ type: 'badge', text: '', reason: '' }, 'instagram');
});
