import { ApiError } from './api.js';

export const HOST_NAME = 'com.northprot.protly';

// connect() returns a Port-like object: { postMessage, onMessage.addListener, onDisconnect.addListener }.
// lastError() returns why a port closed (chrome.runtime.lastError?.message), read inside onDisconnect.
// The returned transport(body) resolves { status, retry_after, body }; transport.ping() resolves
// { ok, key_present, key_shared, workspace_header } from the host without calling the API.
export function createNativeTransport(connect, lastError = () => undefined, timeoutMs = 270000, pingTimeoutMs = 5000) {
  let conn = null; // { port, pending: Map<id, {resolve, reject, timer}> }
  let nextId = 1;

  function open() {
    const port = connect();
    const c = { port, pending: new Map() };
    port.onMessage.addListener((msg) => {
      const p = c.pending.get(msg?.id);
      if (!p) return;
      c.pending.delete(msg.id);
      clearTimeout(p.timer);
      if (p.ping) { p.resolve(msg.ping ? { ping: msg.ping } : {}); return; }
      // An API reply carries an HTTP status (0 for the host's own errors). Anything else is a host bug: a string
      // '200' must not pass as success, and a missing status must not read as the API rejecting the model id.
      if (!Number.isInteger(msg.status) || msg.status < 0 || msg.status > 599) {
        p.reject(new ApiError('host_bug', 'the native host sent a malformed reply'));
        return;
      }
      p.resolve({ status: msg.status, retry_after: msg.retry_after ?? null, body: msg.body });
    });
    port.onDisconnect.addListener(() => {
      const reason = lastError() || 'native host disconnected';
      if (conn === c) conn = null;
      for (const p of c.pending.values()) { clearTimeout(p.timer); p.reject(new ApiError('host', reason)); }
      c.pending.clear();
    });
    return c;
  }

  function send(payload, ms) {
    return new Promise((resolve, reject) => {
      let c;
      try {
        c = conn || (conn = open());
      } catch (e) {
        reject(new ApiError('host', String(e?.message || e)));
        return;
      }
      const id = nextId++;
      const timer = setTimeout(() => {
        if (c.pending.delete(id)) reject(new ApiError('timeout', 'native host timed out'));
      }, ms);
      c.pending.set(id, { resolve, reject, timer, ping: !!payload.ping });
      try {
        c.port.postMessage({ id, ...payload });
      } catch (e) {
        c.pending.delete(id);
        clearTimeout(timer);
        if (conn === c) conn = null;
        reject(new ApiError('host', String(e?.message || e)));
      }
    });
  }

  const transport = (body) => send({ body }, timeoutMs);
  transport.ping = async () => {
    const r = await send({ ping: true }, pingTimeoutMs);
    if (!r.ping) throw new ApiError('host_bug', 'the native host does not answer ping; re-run host/install.sh <extension id>');
    return r.ping;
  };
  return transport;
}
