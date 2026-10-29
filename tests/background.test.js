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
  native.replyWith = null;
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
