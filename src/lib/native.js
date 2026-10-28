import { ApiError } from './api.js';

export const HOST_NAME = 'com.northprot.ig_translate';

// connect() returns a Port-like object: { postMessage, onMessage.addListener, onDisconnect.addListener }.
// lastError() returns why a port closed (chrome.runtime.lastError?.message), read inside onDisconnect.
export function createNativeTransport(connect, lastError = () => undefined, timeoutMs = 150000) {
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

  return function transport(body) {
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
      }, timeoutMs);
      c.pending.set(id, { resolve, reject, timer });
      try {
        c.port.postMessage({ id, body });
      } catch (e) {
        c.pending.delete(id);
        clearTimeout(timer);
        if (conn === c) conn = null;
        reject(new ApiError('host', String(e?.message || e)));
      }
    });
  };
}
