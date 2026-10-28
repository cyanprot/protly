import { test } from 'node:test';
import assert from 'node:assert/strict';
import { callClaude, callJson, ApiError } from '../src/lib/api.js';

const noSleep = async () => {};
function fakeTransport(responses) {
  const calls = [];
  const fn = async (body) => {
    calls.push(body);
    const r = responses.shift();
    if (r instanceof Error) throw r;
    return { status: r.status, retry_after: r.retry_after ?? null, body: r.body ?? {} };
  };
  fn.calls = calls;
  return fn;
}

test('passes the body through unchanged and returns the response body', async () => {
  const t = fakeTransport([{ status: 200, body: { content: [] } }]);
  const r = await callClaude({ model: 'm' }, { transport: t, sleep: noSleep });
  assert.deepEqual(t.calls[0], { model: 'm' });
  assert.deepEqual(r, { content: [] });
});

test('retries 529 twice then fails as overloaded', async () => {
  const t = fakeTransport([{ status: 529 }, { status: 529 }, { status: 529 }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'overloaded');
  assert.equal(t.calls.length, 3);
});

test('429 honours retry_after then succeeds', async () => {
  const waits = [];
  const t = fakeTransport([{ status: 429, retry_after: '3' }, { status: 200, body: { ok: 1 } }]);
  const r = await callClaude({}, { transport: t, sleep: async (ms) => waits.push(ms) });
  assert.deepEqual(r, { ok: 1 });
  assert.deepEqual(waits, [3000]);
});

test('spend-limit 429 does not retry', async () => {
  const t = fakeTransport([{ status: 429, body: { error: { message: 'cap', details: { error_code: 'enforced_spend_limit_reached' } } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'spend_limit');
  assert.equal(t.calls.length, 1);
});

test('401 is auth, no retry', async () => {
  const t = fakeTransport([{ status: 401, body: { error: { message: 'bad key' } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'auth' && e.message === 'bad key');
  assert.equal(t.calls.length, 1);
});

test('status 0 host_config is auth, no retry', async () => {
  const t = fakeTransport([{ status: 0, body: { error: { type: 'host_config', message: 'cannot read API key config' } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'auth' && /API key/.test(e.message));
  assert.equal(t.calls.length, 1);
});

test('status 0 host_network retries then fails as network', async () => {
  const net = { status: 0, body: { error: { type: 'host_network', message: 'down' } } };
  const t = fakeTransport([net, { ...net }, { ...net }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'network');
  assert.equal(t.calls.length, 3);
});

test('transport rejection retries then fails as host', async () => {
  const t = fakeTransport([new ApiError('host', 'gone'), new ApiError('host', 'gone'), new ApiError('host', 'gone')]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'host' && e.message === 'gone');
  assert.equal(t.calls.length, 3);
});

test('callJson re-requests once on parse error', async () => {
  const t = fakeTransport([{ status: 200, body: { n: 1 } }, { status: 200, body: { n: 2 } }]);
  let seen = 0;
  const parse = (resp) => { seen++; if (resp.n === 1) throw new ApiError('parse', 'bad'); return resp.n; };
  assert.equal(await callJson({}, parse, { transport: t, sleep: noSleep }), 2);
  assert.equal(seen, 2);
});

test('callJson gives up after second parse error', async () => {
  const t = fakeTransport([{ status: 200 }, { status: 200 }]);
  const parse = () => { throw new ApiError('parse', 'bad'); };
  await assert.rejects(callJson({}, parse, { transport: t, sleep: noSleep }), (e) => e.kind === 'parse');
  assert.equal(t.calls.length, 2);
});

test('timeouts are not retried (the first attempt may still be billing)', async () => {
  const t1 = fakeTransport([new ApiError('timeout', 'native host timed out')]);
  await assert.rejects(callClaude({}, { transport: t1, sleep: noSleep }), (e) => e.kind === 'timeout');
  assert.equal(t1.calls.length, 1);
  const t2 = fakeTransport([{ status: 0, body: { error: { type: 'host_timeout', message: 'network: timed out' } } }]);
  await assert.rejects(callClaude({}, { transport: t2, sleep: noSleep }), (e) => e.kind === 'timeout');
  assert.equal(t2.calls.length, 1);
});

test('retry_after is capped at 30 s', async () => {
  const waits = [];
  const t = fakeTransport([{ status: 429, retry_after: '600' }, { status: 200, body: {} }]);
  await callClaude({}, { transport: t, sleep: async (ms) => waits.push(ms) });
  assert.deepEqual(waits, [30000]);
});

test('callJson does not re-request a truncated reply', async () => {
  const t = fakeTransport([{ status: 200, body: {} }, { status: 200, body: {} }]);
  const parse = () => { throw new ApiError('truncated', 'Output truncated'); };
  await assert.rejects(callJson({}, parse, { transport: t, sleep: noSleep }), (e) => e.kind === 'truncated');
  assert.equal(t.calls.length, 1);
});

test('host_error is host_bug and is not retried', async () => {
  const t = fakeTransport([{ status: 0, body: { error: { type: 'host_error', message: 'KeyError' } } }]);
  await assert.rejects(callClaude({}, { transport: t, sleep: noSleep }), (e) => e.kind === 'host_bug' && e.message === 'KeyError');
  assert.equal(t.calls.length, 1);
});

test('onUsage sees every 2xx body, including the re-request after a parse failure', async () => {
  const t = fakeTransport([{ status: 200, body: { n: 1 } }, { status: 200, body: { n: 2 } }]);
  const seen = [];
  let first = true;
  const parse = (b) => {
    if (first) { first = false; throw new ApiError('parse', 'not JSON'); }
    return b.n;
  };
  const r = await callJson({}, parse, { transport: t, sleep: noSleep, onUsage: (b) => seen.push(b.n) });
  assert.equal(r, 2);
  assert.deepEqual(seen, [1, 2]);
});

test('onUsage is not called for failed attempts', async () => {
  const t = fakeTransport([{ status: 529 }, { status: 200, body: { n: 1 } }]);
  const seen = [];
  await callClaude({}, { transport: t, sleep: noSleep, onUsage: (b) => seen.push(b.n) });
  assert.deepEqual(seen, [1]);
});

test('a throwing onUsage never fails the call', async () => {
  const t = fakeTransport([{ status: 200, body: { ok: 1 } }]);
  const r = await callClaude({}, { transport: t, sleep: noSleep, onUsage: () => { throw new Error('boom'); } });
  assert.deepEqual(r, { ok: 1 });
});
