import { callJson, ApiError } from './lib/api.js';
import { createNativeTransport, HOST_NAME } from './lib/native.js';
import {
  buildIncomingRequest, buildOutgoingRequest, buildMemoRequest,
  parseIncoming, parseOutgoing, parseMemo,
} from './lib/prompts.js';
import { incomingTarget, resolveOutputLang, latestPartnerLang } from './lib/lang.js';
import { DEFAULT_SETTINGS, withThreadDefaults, threadKey, cacheKey, sentKey, expiredKeys } from './lib/keys.js';

const store = chrome.storage.local;
const BATCH = 20;
const transport = createNativeTransport(
  () => chrome.runtime.connectNative(HOST_NAME),
  () => chrome.runtime.lastError?.message,
);
const api = (body, parse) => callJson(body, parse, { transport });

async function getSettings() {
  const { settings } = await store.get('settings');
  return {
    models: { ...DEFAULT_SETTINGS.models, ...settings?.models },
    threadDefaults: { ...DEFAULT_SETTINGS.threadDefaults, ...settings?.threadDefaults },
  };
}

async function getThread(threadId, settings) {
  const k = threadKey(threadId);
  const got = await store.get(k);
  return withThreadDefaults(got[k] || {}, (settings || (await getSettings())).threadDefaults);
}

async function setThread(threadId, patch) {
  const k = threadKey(threadId);
  const got = await store.get(k);
  await store.set({ [k]: { ...(got[k] || {}), ...patch } });
  return getThread(threadId);
}

async function incoming({ threadId, context, items, updateLang }) {
  const settings = await getSettings();
  const thread = await getThread(threadId, settings);
  const keys = await Promise.all(items.map((it) => cacheKey(threadId, it.text, thread.otherTarget)));
  const hits = await store.get(keys);
  const out = {};
  const misses = [];
  items.forEach((it, i) => {
    const h = hits[keys[i]];
    if (h) out[it.id] = h; else misses.push({ it, key: keys[i] });
  });

  for (let i = 0; i < misses.length; i += BATCH) {
    const chunk = misses.slice(i, i + BATCH);
    const body = buildIncomingRequest({
      model: settings.models.incoming, memo: thread.memo, context,
      otherTarget: thread.otherTarget, items: chunk.map((m) => m.it),
    });
    const res = await api(body, parseIncoming);
    const writes = {};
    for (const { it, key } of chunk) {
      const r = res[it.id];
      if (!r) continue;
      const entry = { src_lang: r.src_lang, translation: r.translation, ts: Date.now() };
      writes[key] = entry;
      out[it.id] = entry;
    }
    await store.set(writes);
  }

  if (updateLang) {
    const ordered = items.filter((it) => out[it.id]).map((it) => ({ from: it.from, src_lang: out[it.id].src_lang }));
    const lang = latestPartnerLang(ordered);
    if (lang && lang !== thread.partnerLang) await setThread(threadId, { partnerLang: lang });
  }

  const data = {};
  for (const it of items) {
    const r = out[it.id];
    data[it.id] = r && incomingTarget(r.src_lang, thread.otherTarget) ? { src_lang: r.src_lang, translation: r.translation } : null;
  }
  return data;
}

async function outgoing({ threadId, context, korean, profile, lang }) {
  const settings = await getSettings();
  const thread = await getThread(threadId, settings);
  const target = lang || resolveOutputLang(thread);
  const model = profile === 'hard' ? settings.models.hard : settings.models.outgoing;
  const body = buildOutgoingRequest({ model, profile, memo: thread.memo, context, korean, lang: target });
  const r = await api(body, parseOutgoing);
  return { ...r, lang: target, model };
}

async function suggestMemo({ context }) {
  const settings = await getSettings();
  return api(buildMemoRequest({ model: settings.models.outgoing, context }), parseMemo);
}

async function sent({ threadId, text, korean }) {
  await store.set({ [await sentKey(threadId, text)]: { korean, ts: Date.now() } });
  return true;
}

async function lookupSent({ threadId, texts }) {
  const keys = await Promise.all(texts.map((t) => sentKey(threadId, t)));
  const got = await store.get(keys);
  const out = {};
  texts.forEach((t, i) => { if (got[keys[i]]) out[t] = got[keys[i]].korean; });
  return out;
}

const handlers = {
  getThread: ({ threadId }) => getThread(threadId),
  setThread: ({ threadId, patch }) => setThread(threadId, patch),
  incoming, outgoing, suggestMemo, sent, lookupSent,
  badge: async ({ text }, sender) => { await chrome.action.setBadgeText({ text, tabId: sender.tab?.id }); return true; },
};

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const h = handlers[msg?.type];
  if (!h) return false;
  Promise.resolve(h(msg, sender))
    .then((data) => sendResponse({ ok: true, data }))
    .catch((e) => sendResponse({ ok: false, error: { kind: e instanceof ApiError ? e.kind : 'internal', message: String(e?.message || e) } }));
  return true;
});

async function prune() {
  const all = await store.get(null);
  const dead = expiredKeys(all, Date.now());
  if (dead.length) await store.remove(dead);
}
chrome.runtime.onStartup.addListener(prune);
chrome.runtime.onInstalled.addListener(prune);
