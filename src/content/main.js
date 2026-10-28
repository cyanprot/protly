import { threadIdFromPath } from '../lib/keys.js';
import { isKoreanOnly } from '../lib/lang.js';
import { classifyAdded } from '../lib/classify.js';
import { findViewerName } from './selectors.js';
import {
  findThreadRoot, readMessages, renderTranslation, renderRetry, setHoverOriginal, clearTranslation,
  clearAllTranslations, stillShows,
} from './dom.js';

const CONTEXT_N = 30;
const DEBOUNCE_MS = 400;
const WAIT_MS = 300;
const WAIT_TRIES = 33; // about 10 s

const ERROR_BANNERS = {
  auth: 'ig-translate: API key missing or rejected. Check ~/.config/anthropic/api-key.',
  host: 'ig-translate: native host not reachable. Run host/install.sh <extension id>, then reload the extension.',
  spend_limit: 'ig-translate: monthly API spend limit reached. Translation paused until the limit resets.',
  host_bug: 'ig-translate: the native host hit an error',
  bad_request: 'ig-translate: the API rejected the request (check the model ids in Options)',
  stale: 'ig-translate was reloaded or updated. Reload this tab.',
};

// Banner text for an error from ask(), or null when a per-message marker is enough.
export function bannerFor(e) {
  const base = ERROR_BANNERS[e?.kind];
  if (!base) return null;
  return ['host_bug', 'bad_request'].includes(e.kind) ? `${base}: ${e.message}` : base;
}

export const ask = async (msg) => {
  let r;
  try {
    if (!chrome.runtime?.id) throw new Error('Extension context invalidated.');
    r = await chrome.runtime.sendMessage(msg);
  } catch (err) {
    const e = new Error(err?.message || String(err));
    e.kind = /context invalidated|Receiving end does not exist/i.test(e.message) ? 'stale' : 'internal';
    if (e.kind === 'stale') showBanner(ERROR_BANNERS.stale);
    throw e;
  }
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
};

export const initHooks = [];
let current = null; // { threadId, thread, root, observer, known, timer, onTeardown, onThreadUpdate, onMutate }
// Text signature of the thread we just left. Instagram reuses row nodes across threads, so node identity
// cannot tell old rows from new ones; the visible texts can.
let staleSig = null;
const sigOf = (msgs) => msgs.map((m) => m.text).join('\u0001');
const bannersShown = new Set();

export async function start() {
  const [{ mountPanel }, { mountOutgoing }] = await Promise.all([import('./panel.js'), import('./outgoing.js')]);
  initHooks.push(mountPanel, mountOutgoing);
  let lastPath = null;
  const tick = () => {
    if (location.pathname === lastPath) return;
    lastPath = location.pathname;
    teardown();
    const id = threadIdFromPath(location.pathname);
    if (id) waitForThread(id);
  };
  tick();
  setInterval(tick, 500); // SPA navigation: poll the path; cheap and reliable
}

function teardown() {
  if (!current) return;
  current.observer?.disconnect();
  staleSig = sigOf(readMessages(current.root));
  clearAllTranslations(current.root);
  clearTimeout(current.timer);
  current.onTeardown.forEach((f) => f());
  current = null;
}

function waitForThread(threadId, tries = 0, lastSig = null) {
  if (threadIdFromPath(location.pathname) !== threadId) return; // navigated away meanwhile
  // No viewer name means senders cannot be told apart: treat it like a missing root (selector miss).
  const root = findViewerName(document) ? findThreadRoot(document) : null;
  const msgs = root ? readMessages(root) : [];
  const sig = sigOf(msgs);
  const clean = msgs.length === 0 || sig !== staleSig;
  // Same texts over two checks; an empty thread (new chat) must stay empty for about 1 s.
  if (root && clean && sig === lastSig && (msgs.length > 0 || tries >= 3)) return initThread(threadId, root);
  if (tries >= WAIT_TRIES) {
    if (root) {
      if (!clean) console.warn('[igt] old thread rows still present after 10 s; initialising anyway');
      return initThread(threadId, root);
    }
    ask({ type: 'badge', text: '!' }).catch(() => {});
    console.warn('[igt] thread root not found; extension inactive on this page');
    return;
  }
  setTimeout(() => waitForThread(threadId, tries + 1, clean ? sig : null), WAIT_MS);
}

async function initThread(threadId, root) {
  let thread;
  try {
    thread = await ask({ type: 'getThread', threadId });
  } catch (e) {
    ask({ type: 'badge', text: '!' }).catch(() => {});
    showBanner(bannerFor(e) || `ig-translate: could not load thread settings: ${e.message}`);
    return;
  }
  if (threadIdFromPath(location.pathname) !== threadId) return;
  teardown(); // anything a racing init set up meanwhile
  ask({ type: 'badge', text: '' }).catch(() => {});
  current = {
    threadId, thread, root, known: new WeakMap(), timer: null, // row -> text it was seen with
    freshRows: new WeakSet(), // rows that arrived as new messages: rendered with newMode
    onTeardown: [], onThreadUpdate: [], onMutate: [],
  };

  const msgs = readMessages(root);
  msgs.forEach((m) => current.known.set(m.row, m.text));
  if (thread.enabled) {
    translate(msgs, thread.pastMode, true);
    hoverSent(msgs);
  }

  current.observer = new MutationObserver(() => onMutate(threadId));
  current.observer.observe(root, { childList: true, subtree: true });

  for (const f of initHooks) f(current);
}

function onMutate(threadId) {
  if (!current || current.threadId !== threadId) return;
  clearTimeout(current.timer);
  current.timer = setTimeout(() => {
    if (!current || current.threadId !== threadId) return;
    current.onMutate.forEach((f) => f());
    const msgs = readMessages(current.root);
    // A row counts as known only with the same text: a reused node showing another message is new.
    const { past, fresh } = classifyAdded(msgs, (m) => current.known.get(m.row) === m.text);
    for (const m of [...past, ...fresh]) { current.known.set(m.row, m.text); clearTranslation(m); }
    past.forEach((m) => current.freshRows.delete(m.row));
    fresh.forEach((m) => current.freshRows.add(m.row));
    if (!current.thread.enabled) return;
    translate(past, current.thread.pastMode, false);
    translate(fresh, current.thread.newMode, true);
    hoverSent([...past, ...fresh]);
  }, DEBOUNCE_MS);
}

export function contextFor(root) {
  return readMessages(root).slice(-CONTEXT_N).map(({ from, text }) => ({ from, text }));
}

// updateLang: true only for the initial scan and fresh arrivals (see Task 12).
async function translate(msgs, mode, updateLang) {
  if (!current) return;
  const todo = msgs.filter((m) => m.from === 'partner' && !isKoreanOnly(m.text));
  if (!todo.length) return;
  const threadId = current.threadId;
  const items = todo.map((m, i) => ({ id: String(i), text: m.text, from: m.from }));
  try {
    const data = await ask({ type: 'incoming', threadId, context: contextFor(current.root), items, updateLang });
    if (current?.threadId !== threadId) return;
    todo.forEach((m, i) => {
      const r = data[String(i)];
      if (!r || !stillShows(m)) return;
      if (r.missing) renderRetry(m, () => translate([m], mode, false));
      else renderTranslation(m, r.translation, mode);
    });
    if (updateLang) {
      const t = await ask({ type: 'getThread', threadId }); // partnerLang may have changed
      if (current?.threadId === threadId) current.thread = t;
    }
  } catch (e) {
    if (current?.threadId !== threadId) return;
    if (bannerFor(e)) showBanner(bannerFor(e));
    todo.forEach((m) => { if (stillShows(m)) renderRetry(m, () => translate([m], mode, false)); });
  }
}

async function hoverSent(msgs) {
  const mine = msgs.filter((m) => m.from === 'me');
  if (!mine.length || !current) return;
  const threadId = current.threadId;
  try {
    const map = await ask({ type: 'lookupSent', threadId, texts: mine.map((m) => m.text) });
    if (current?.threadId !== threadId) return;
    for (const m of mine) if (map[m.text] && stillShows(m)) setHoverOriginal(m, map[m.text]);
  } catch {}
}

// Re-render everything after a panel toggle change.
export function rerender() {
  if (!current) return;
  const msgs = readMessages(current.root);
  msgs.forEach(clearTranslation);
  if (!current.thread.enabled) return;
  const isFresh = (m) => current.freshRows.has(m.row);
  translate(msgs.filter((m) => !isFresh(m)), current.thread.pastMode, false); // cache makes this cheap
  translate(msgs.filter(isFresh), current.thread.newMode, false);
  hoverSent(msgs);
}

export function showBanner(text) {
  if (bannersShown.has(text)) return;
  bannersShown.add(text);
  const b = document.createElement('div');
  b.style.cssText = 'position:fixed;top:12px;right:12px;z-index:99999;max-width:360px;background:#222;color:#fff;padding:10px 14px;border-radius:8px;font:13px system-ui;cursor:pointer';
  b.textContent = text;
  b.title = 'Click to dismiss';
  b.onclick = () => b.remove();
  document.body.appendChild(b);
}

export const getCurrent = () => current;
