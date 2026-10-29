import { ApiError } from './api.js';

// The background's chrome.runtime.onMessage listener. handlers maps a command name to (msg, sender) => result.
// Only own string keys are commands: a plain-object lookup would also dispatch 'constructor' or 'toString'.
// Replies { ok: true, data } or { ok: false, error: { kind, message } }; anything else gets no answer.
export function createRouter({ handlers }) {
  return (msg, sender, sendResponse) => {
    const type = msg?.type;
    if (typeof type !== 'string' || !Object.hasOwn(handlers, type)) return false;
    Promise.resolve()
      .then(() => handlers[type](msg, sender))
      .then((data) => sendResponse({ ok: true, data }))
      .catch((e) => sendResponse({ ok: false, error: { kind: e instanceof ApiError ? e.kind : 'internal', message: String(e?.message || e) } }));
    return true;
  };
}
