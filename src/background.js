import { callClaude, callJson, ApiError } from './lib/api.js';
import { createUsageRecorder, summarize } from './lib/usage.js';
import { createBadgeStore } from './lib/badge.js';
import { statusFor } from './lib/status.js';
import { DEFAULT_SITES } from './lib/flags.js';
import { routeCommand } from './lib/route.js';
import { createRouter } from './lib/messages.js';
import { createNativeTransport, HOST_NAME } from './lib/native.js';
import {
  buildIncomingRequest, buildOutgoingRequest, buildMemoRequest, buildEmailRequest, buildPolishRequest,
  buildBoxRequest, buildSelectionRequest, parseIncoming, parseOutgoing, parseMemo, parseEmail,
} from './lib/prompts.js';
import { incomingTarget, resolveOutputLang, latestPartnerLang } from './lib/lang.js';
import { DEFAULT_SETTINGS, withThreadDefaults, threadKey, cacheKey, sentKey, expiredKeys } from './lib/keys.js';

const store = chrome.storage.local;
const BATCH = 20;
const transport = createNativeTransport(
  () => chrome.runtime.connectNative(HOST_NAME),
  () => chrome.runtime.lastError?.message,
);
const usageLog = createUsageRecorder({
  get: async () => (await store.get('usage')).usage,
  set: (usage) => store.set({ usage }),
});
const apiOpts = { transport, onUsage: usageLog.record };
const api = (body, parse) => callJson(body, parse, apiOpts);
const badges = createBadgeStore(chrome.storage.session);

async function getSettings() {
  const { settings } = await store.get('settings');
  return {
    models: { ...DEFAULT_SETTINGS.models, ...Object.fromEntries(Object.entries(settings?.models || {}).filter(([, v]) => v)) },
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
    try {
      await store.set(writes);
    } catch (e) {
      console.warn('[protly] cache write failed; translations still returned', e); // the call is already billed
    }
  }

  if (updateLang) {
    const ordered = items.filter((it) => out[it.id]).map((it) => ({ from: it.from, src_lang: out[it.id].src_lang }));
    const lang = latestPartnerLang(ordered);
    if (lang && lang !== thread.partnerLang) await setThread(threadId, { partnerLang: lang });
  }

  const data = {};
  for (const it of items) {
    const r = out[it.id];
    if (!r) { data[it.id] = { missing: true }; continue; } // model skipped it or returned nothing
    data[it.id] = incomingTarget(r.src_lang, thread.otherTarget) ? { src_lang: r.src_lang, translation: r.translation } : null;
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

// Gmail drafts. No storage: nothing is cached or remembered per thread.
async function email({ context, korean, profile, lang }) {
  const settings = await getSettings();
  const hard = profile === 'hard';
  const model = hard ? settings.models.hard : settings.models.outgoing;
  const body = buildEmailRequest({ model, profile: hard ? 'hard' : 'email', context, korean, lang: lang || 'auto' });
  const r = await api(body, parseEmail);
  return { ...r, model };
}

// English polish (Instagram and Gmail). No storage, like email.
async function polish({ text, profile }) {
  const settings = await getSettings();
  const hard = profile === 'hard';
  const model = hard ? settings.models.hard : settings.models.outgoing;
  const r = await api(buildPolishRequest({ model, profile: hard ? 'hard' : 'polish', draft: text }), parseOutgoing);
  return { ...r, model };
}

// Any-site text box. Stateless like email and polish: nothing cached, nothing remembered.
async function box({ text, lang, profile, hostname }) {
  const settings = await getSettings();
  const hard = profile === 'hard';
  const model = hard ? settings.models.hard : settings.models.outgoing;
  const target = lang || 'en';
  const body = buildBoxRequest({ model, profile: hard ? 'hard' : 'outgoing', korean: text, lang: target, hostname });
  const r = await api(body, parseOutgoing);
  return { ...r, lang: target, model };
}

// A selection on any page, to Korean. Never the thread-keyed incoming handler: no c: cache, no partnerLang.
async function selection({ text }) {
  const settings = await getSettings();
  const res = await api(buildSelectionRequest({ model: settings.models.incoming, text }), parseIncoming);
  const r = res['0'];
  if (!r) throw new ApiError('parse', 'no translation returned');
  return { src_lang: r.src_lang, translation: r.src_lang === 'ko' ? text : r.translation };
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

// text '' clears the reason too: SPA navigation may never fire a 'loading' update.
async function setTabBadge(tabId, text, reason) {
  if (tabId == null) return; // an undefined tabId would set the badge on every tab
  await chrome.action.setBadgeText({ text, tabId });
  await badges.set(tabId, { text, reason });
}

const handlers = {
  getThread: ({ threadId }) => getThread(threadId),
  setThread: ({ threadId, patch }) => setThread(threadId, patch),
  incoming, outgoing, email, polish, box, selection, suggestMemo, sent, lookupSent,
  tabStatus: async ({ tabId, url }) => {
    const { sites } = await store.get('sites');
    return statusFor({ url, sites: { ...DEFAULT_SITES, ...sites }, badge: tabId == null ? null : await badges.get(tabId) });
  },
  diag: () => transport.ping(),
  // One tiny real request through the normal path (metered like any other call).
  testCall: async () => {
    const settings = await getSettings();
    const model = settings.models.outgoing;
    const t0 = Date.now();
    const body = await callClaude(
      { model, max_tokens: 16, messages: [{ role: 'user', content: 'Reply with OK.' }] },
      apiOpts,
    );
    return { model: body?.model || model, ms: Date.now() - t0 };
  },
  usageSummary: async () => summarize((await store.get('usage')).usage || {}, Date.now()),
  badge: async ({ text, reason }, sender) => { await setTabBadge(sender.tab?.id, text, reason); return true; },
};

chrome.runtime.onMessage.addListener(createRouter({ handlers, extensionId: chrome.runtime.id }));

const GENERIC = 'dist/generic.js';
const inFrame = (tabId, frameId) => ({ tabId, frameIds: [frameId] });

// Ask the Instagram/Gmail adapter in that frame first; inject the generic bundle only when none owns the box.
function route(tab, frameId, args) {
  return routeCommand({
    tabId: tab.id, frameId, args,
    sendToTab: (tabId, msg, f) => chrome.tabs.sendMessage(tabId, msg, { frameId: f }),
    injectFile: (tabId, f) => chrome.scripting.executeScript({ target: inFrame(tabId, f), files: [GENERIC] }),
    runGeneric: (tabId, f, a) => chrome.scripting.executeScript({
      target: inFrame(tabId, f), func: (x) => globalThis.__protly.run(x), args: [a],
    }),
    setBadge: (tabId, text, reason) => setTabBadge(tabId, text, reason),
    toastInMain: (tabId, text) => chrome.scripting.executeScript({
      target: inFrame(tabId, 0), func: (t) => globalThis.__protly.toast(t), args: [text],
    }),
  }).catch((e) => console.warn('[protly] routing failed', e));
}

chrome.commands.onCommand.addListener((command, tab) => {
  if (command === 'run' && tab?.id != null) route(tab, 0, { source: 'command' });
});

chrome.runtime.onInstalled.addListener(() => {
  // removeAll first: a reload re-runs onInstalled and duplicate ids would throw.
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: 'protly-selection', title: 'protly: translate selection', contexts: ['selection'] });
    chrome.contextMenus.create({ id: 'protly-box', title: 'protly: translate or polish this box', contexts: ['editable'] });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (tab?.id == null) return;
  const source = info.menuItemId === 'protly-selection' ? 'menu-selection' : 'menu-editable';
  route(tab, info.frameId ?? 0, { source, selectionText: info.selectionText });
});

async function prune() {
  const all = await store.get(null);
  const dead = expiredKeys(all, Date.now());
  if (dead.length) await store.remove(dead);
}
chrome.runtime.onStartup.addListener(prune);
chrome.runtime.onInstalled.addListener(prune);
chrome.tabs.onUpdated.addListener((tabId, info) => { if (info.status === 'loading') badges.clear(tabId); });
chrome.tabs.onRemoved.addListener((tabId) => badges.clear(tabId));
