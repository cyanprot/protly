import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createNativeTransport } from '../src/lib/native.js';

function fakePort() {
  const msgL = [];
  const discL = [];
  return {
    sent: [],
    postMessage(m) { this.sent.push(m); },
    onMessage: { addListener: (f) => msgL.push(f) },
    onDisconnect: { addListener: (f) => discL.push(f) },
    reply(m) { msgL.forEach((f) => f(m)); },
    disconnect() { discL.forEach((f) => f()); },
  };
}

function setup(lastError, timeoutMs) {
  const ports = [];
  const t = createNativeTransport(() => { const p = fakePort(); ports.push(p); return p; }, lastError, timeoutMs);
  return { t, ports };
}

test('one port, replies matched by id', async () => {
  const { t, ports } = setup();
  const a = t({ n: 1 });
  const b = t({ n: 2 });
  assert.equal(ports.length, 1);
  const [ma, mb] = ports[0].sent;
  assert.deepEqual(ma.body, { n: 1 });
  assert.notEqual(ma.id, mb.id);
  ports[0].reply({ id: mb.id, status: 200, retry_after: null, body: { n: 2 } });
  ports[0].reply({ id: ma.id, status: 429, retry_after: '3', body: {} });
  assert.deepEqual(await b, { status: 200, retry_after: null, body: { n: 2 } });
  assert.deepEqual(await a, { status: 429, retry_after: '3', body: {} });
});

test('unknown reply ids are ignored', async () => {
  const { t, ports } = setup();
  const a = t({});
  ports[0].reply({ id: 999, status: 200, body: {} });
  ports[0].reply({ id: ports[0].sent[0].id, status: 200, retry_after: null, body: { ok: 1 } });
  assert.deepEqual((await a).body, { ok: 1 });
});

test('disconnect rejects pending with host kind; next call reconnects', async () => {
  const { t, ports } = setup(() => 'Specified native messaging host not found.');
  const a = t({});
  ports[0].disconnect();
  await assert.rejects(a, (e) => e.kind === 'host' && /not found/.test(e.message));
  const b = t({});
  assert.equal(ports.length, 2);
  ports[1].reply({ id: ports[1].sent[0].id, status: 200, retry_after: null, body: {} });
  assert.equal((await b).status, 200);
});

test('connect throwing rejects with host kind', async () => {
  const t = createNativeTransport(() => { throw new Error('nativeMessaging permission missing'); });
  await assert.rejects(t({}), (e) => e.kind === 'host' && /permission/.test(e.message));
});

test('no reply rejects after the timeout', async () => {
  const { t } = setup(undefined, 20);
  await assert.rejects(t({}), (e) => e.kind === 'timeout' && /timed out/.test(e.message));
});

test('ping posts {id, ping: true} with no body and resolves the ping object', async () => {
  const { t, ports } = setup();
  const p = t.ping();
  const sent = ports[0].sent[0];
  assert.equal(sent.ping, true);
  assert.equal('body' in sent, false);
  ports[0].reply({ id: sent.id, ping: { ok: true, key_present: true, workspace_header: false } });
  assert.deepEqual(await p, { ok: true, key_present: true, workspace_header: false });
});

test('an old host that answers a ping like an API call is a host_bug', async () => {
  const { t, ports } = setup();
  const p = t.ping();
  const id = ports[0].sent[0].id;
  ports[0].reply({ id, status: 0, retry_after: null, body: { error: { type: 'host_error', message: 'KeyError' } } });
  await assert.rejects(p, (e) => e.kind === 'host_bug' && /install\.sh/.test(e.message));
});

test('ping times out on its own short timer', async () => {
  const t = createNativeTransport(() => fakePort(), undefined, 270000, 20);
  await assert.rejects(t.ping(), (e) => e.kind === 'timeout');
});

test('API requests still post {id, body} and resolve {status, retry_after, body}', async () => {
  const { t, ports } = setup();
  const a = t({ model: 'm' });
  const sent = ports[0].sent[0];
  assert.deepEqual(Object.keys(sent).sort(), ['body', 'id']);
  ports[0].reply({ id: sent.id, status: 200, body: { ok: 1 } });
  assert.deepEqual(await a, { status: 200, retry_after: null, body: { ok: 1 } });
});
