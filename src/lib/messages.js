import { ApiError } from './api.js';

export const INSTAGRAM = 'https://www.instagram.com';
export const GMAIL = 'https://mail.google.com';
export const PAGE = 'extension page'; // the popup and the options page
export const ANY_SITE = 'any site'; // a content script in a tab on any http(s) origin (the generic Alt+T bundle)

// Who may send each command. A command missing here is refused. Content scripts run inside hostile pages, so each
// one gets only what its own adapter calls: thread state is Instagram's, email is Gmail's, the popup and options
// commands (a billed test call, spend, other tabs' status) are for extension pages only.
export const SENDERS = {
  getThread: [INSTAGRAM], setThread: [INSTAGRAM], incoming: [INSTAGRAM], outgoing: [INSTAGRAM],
  suggestMemo: [INSTAGRAM], sent: [INSTAGRAM], lookupSent: [INSTAGRAM],
  email: [GMAIL],
  badge: [INSTAGRAM, GMAIL],
  polish: [ANY_SITE], box: [ANY_SITE], selection: [ANY_SITE],
  tabStatus: [PAGE], diag: [PAGE], testCall: [PAGE], usageSummary: [PAGE],
};

// PAGE, the http(s) origin of a content script's frame, or null for anything else (another extension, no tab).
export function senderClass(sender, extensionId) {
  if (!sender || !extensionId || sender.id !== extensionId) return null;
  if (typeof sender.url === 'string' && sender.url.startsWith(`chrome-extension://${extensionId}/`)) return PAGE;
  if (sender.tab?.id == null) return null;
  let origin = sender.origin;
  if (typeof origin !== 'string') {
    try { origin = new URL(sender.url).origin; } catch { return null; }
  }
  return /^https?:\/\/[^/]+$/.test(origin) ? origin : null;
}

export function allowed(type, sender, extensionId, senders = SENDERS) {
  const from = senderClass(sender, extensionId);
  const list = Object.hasOwn(senders, type) ? senders[type] : [];
  return from != null && (list.includes(from) || (from !== PAGE && list.includes(ANY_SITE)));
}

const reply = (sendResponse, e) => sendResponse({
  ok: false, error: { kind: e instanceof ApiError ? e.kind : 'internal', message: String(e?.message || e) },
});

// The background's chrome.runtime.onMessage listener. handlers maps a command name to (msg, sender) => result.
// Only own string keys are commands: a plain-object lookup would also dispatch 'constructor' or 'toString'.
// Replies { ok: true, data } or { ok: false, error: { kind, message } }; anything else gets no answer.
export function createRouter({ handlers, extensionId, senders = SENDERS }) {
  return (msg, sender, sendResponse) => {
    const type = msg?.type;
    if (typeof type !== 'string' || !Object.hasOwn(handlers, type)) return false;
    if (!allowed(type, sender, extensionId, senders)) {
      reply(sendResponse, new ApiError('forbidden', `${type} is not available to this sender`));
      return false;
    }
    Promise.resolve()
      .then(() => handlers[type](msg, sender))
      .then((data) => sendResponse({ ok: true, data }))
      .catch((e) => reply(sendResponse, e));
    return true;
  };
}
