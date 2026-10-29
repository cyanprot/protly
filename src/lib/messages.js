import { ApiError } from './api.js';
import { LIMITS } from './limits.js';

export { LIMITS };

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

// Message shapes. Content scripts pass page text (messages, drafts, the thread) and their own UI state; the checks
// keep the documented fields, types and enum values, and bound the sizes so a hostile page cannot make one
// command arbitrarily large or write arbitrary fields into stored thread state.
const LANG = /^[a-z]{2,12}$/; // ISO 639 codes; also any stored partner language from before src_lang was checked
const THREAD_ID = /^[^/\s]{1,128}$/;
const ITEM_ID = /^[\w-]{1,32}$/;
const HOSTNAME = /^[\w.:[\]-]{0,253}$/;

const str = (max, min = 0) => (v) => typeof v === 'string' && v.length >= min && v.length <= max;
const match = (re) => (v) => typeof v === 'string' && re.test(v);
const oneOf = (...vals) => (v) => vals.includes(v);
const opt = (f) => (v) => v == null || f(v);
const bool = (v) => typeof v === 'boolean';
const isObject = (v) => v != null && typeof v === 'object' && !Array.isArray(v);
const record = (fields) => (v) => isObject(v) && Object.entries(fields).every(([k, f]) => f(v[k]));
const listOf = (max, f) => (v) => Array.isArray(v) && v.length <= max && v.every(f);

const text = str(LIMITS.text);
const someText = str(LIMITS.text, 1);
const lang = match(LANG);
const autoOrLang = (v) => v === 'auto' || lang(v);
const threadId = match(THREAD_ID);
const context = listOf(LIMITS.context, record({ from: oneOf('me', 'partner', 'them'), text }));

// setThread: only the fields the thread panel and the language chip change, at least one of them.
const PATCH = {
  enabled: bool, outputLang: autoOrLang, otherTarget: oneOf('ko', 'en'),
  pastMode: oneOf('replace', 'below'), newMode: oneOf('below', 'replace'), memo: str(LIMITS.memo),
};
const patch = (v) => isObject(v) && Object.keys(v).length > 0
  && Object.entries(v).every(([k, x]) => Object.hasOwn(PATCH, k) && PATCH[k](x));

export const SHAPES = {
  getThread: { threadId },
  setThread: { threadId, patch },
  incoming: {
    threadId, context, updateLang: opt(bool),
    items: listOf(LIMITS.items, record({ id: match(ITEM_ID), text, from: oneOf('me', 'partner') })),
  },
  outgoing: { threadId, context, korean: someText, profile: oneOf('outgoing', 'hard'), lang: opt(lang) },
  suggestMemo: { threadId, context },
  sent: { threadId, text: someText, korean: opt(text) },
  lookupSent: { threadId, texts: listOf(LIMITS.texts, text) },
  email: { context, korean: someText, profile: oneOf('email', 'hard'), lang: opt(autoOrLang) },
  polish: { text: someText, profile: opt(oneOf('outgoing', 'polish', 'email', 'hard')) },
  box: { text: someText, lang: opt(lang), profile: opt(oneOf('outgoing', 'hard')), hostname: opt(match(HOSTNAME)) },
  selection: { text: someText },
  badge: { text: oneOf('', '!'), reason: opt(str(LIMITS.reason)) },
  tabStatus: { tabId: opt(Number.isInteger), url: opt(str(LIMITS.url)) },
  diag: {}, testCall: {}, usageSummary: {},
};

// Throws ApiError('bad_message') naming the first field that does not fit. A command without a shape is refused.
export function checkShape(type, msg, shapes = SHAPES) {
  if (!Object.hasOwn(shapes, type)) throw new ApiError('bad_message', `${type}: no message shape`);
  for (const [field, ok] of Object.entries(shapes[type])) {
    if (!ok(msg[field])) throw new ApiError('bad_message', `${type}: bad ${field}`);
  }
}

const reply = (sendResponse, e) => sendResponse({
  ok: false, error: { kind: e instanceof ApiError ? e.kind : 'internal', message: String(e?.message || e) },
});

// The background's chrome.runtime.onMessage listener. handlers maps a command name to (msg, sender) => result.
// Only own string keys are commands: a plain-object lookup would also dispatch 'constructor' or 'toString'.
// Replies { ok: true, data } or { ok: false, error: { kind, message } }; anything else gets no answer.
export function createRouter({ handlers, extensionId, senders = SENDERS, shapes = SHAPES }) {
  return (msg, sender, sendResponse) => {
    const type = msg?.type;
    if (typeof type !== 'string' || !Object.hasOwn(handlers, type)) return false;
    if (!allowed(type, sender, extensionId, senders)) {
      reply(sendResponse, new ApiError('forbidden', `${type} is not available to this sender`));
      return false;
    }
    Promise.resolve()
      .then(() => { checkShape(type, msg, shapes); return handlers[type](msg, sender); })
      .then((data) => sendResponse({ ok: true, data }))
      .catch((e) => reply(sendResponse, e));
    return true;
  };
}
