import { GSEL, composeOf, findViewerEmail } from './selectors.js';
import { userNodes, nodesToText, textToNodes, replaceUserNodes, hasMedia } from './body.js';
import { readThread } from './thread.js';
import { hasHangul, LANG_NAMES } from '../../lib/lang.js';

const ERRORS = {
  auth: 'API key missing or rejected. Check ~/.config/anthropic/api-key.',
  host: 'Native host not reachable. Run host/install.sh <extension id>, then reload the extension.',
  spend_limit: 'Monthly API spend limit reached.',
  timeout: 'The model took too long. Try again.',
};
const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');
const states = new WeakMap(); // compose body -> state; dropped with the compose
const mounted = new WeakSet();

async function ask(msg) {
  const r = await chrome.runtime.sendMessage(msg);
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
}

function stateOf(body) {
  let s = states.get(body);
  if (!s) {
    s = { mode: 'idle', reqId: 0, saved: null, korean: null, shown: null, lang: 'auto', profile: 'email', note: null, anchor: null };
    states.set(body, s);
  }
  return s;
}

export function mountCompose(body) {
  if (mounted.has(body)) return;
  mounted.add(body);
  const s = stateOf(body);
  const sendCell = composeOf(body)?.querySelector(GSEL.send)?.closest('td');
  if (!sendCell) {
    console.warn('[igt] Gmail Send button not found; Translate button not mounted (Alt+T still works)');
    ask({ type: 'badge', text: '!' }).catch(() => {});
    return;
  }
  s.anchor = sendCell.closest('table');
  const td = document.createElement('td');
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'igt-g-btn';
  btn.textContent = 'Translate';
  btn.title = 'Translate the Korean draft (Alt+T)';
  btn.addEventListener('click', () => translate(body));
  td.appendChild(btn);
  sendCell.after(td);
}

const span = (t) => { const e = document.createElement('span'); e.textContent = t; return e; };
function button(label, onClick) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = label;
  b.addEventListener('click', onClick);
  return b;
}

function showNote(body, s, children, isError = false) {
  if (!s.note?.isConnected) {
    s.note = document.createElement('div');
    s.note.className = 'igt-g-note';
    if (s.anchor?.isConnected) s.anchor.before(s.note); else body.after(s.note);
  }
  s.note.classList.toggle('igt-g-err', isError);
  s.note.replaceChildren(...children);
}

function hideNote(s) {
  s.note?.remove();
  s.note = null;
}

function langPicker(body, current) {
  const sel = document.createElement('select');
  const codes = Object.keys(LANG_NAMES).filter((c) => c !== 'ko');
  if (!codes.includes(current)) codes.unshift(current);
  for (const c of codes) {
    const o = document.createElement('option');
    o.value = c;
    o.textContent = LANG_NAMES[c] || c;
    o.selected = c === current;
    sel.appendChild(o);
  }
  sel.addEventListener('change', () => retranslate(body, { lang: sel.value }));
  return sel;
}

function showPreview(body, s, r) {
  showNote(body, s, [
    span(`${r.back_translation}  · ${modelLabel(r.model)}`),
    langPicker(body, r.lang),
    button('Opus', () => retranslate(body, { profile: 'hard' })),
    button('Undo', () => undo(body)),
  ]);
}

// Translate button and Alt+T.
export function translate(body) {
  const s = stateOf(body);
  if (s.mode === 'translating') return;
  const nodes = userNodes(body);
  const text = nodesToText(nodes).trim();
  if (s.mode === 'preview') {
    if (!hasHangul(text) || norm(text) === norm(s.shown)) return; // nothing new to translate
    Object.assign(s, { mode: 'idle', saved: null }); // a new Korean draft replaced the preview
  }
  if (!hasHangul(text)) return showNote(body, s, [span('No Korean text to translate.')], true);
  if (hasMedia(nodes)) return showNote(body, s, [span('The draft contains images. Translate the text before adding images.')], true);
  return request(body, { korean: text, profile: 'email', lang: 'auto' });
}

// Picker and Opus in preview: same Korean, other language or model.
function retranslate(body, { lang, profile }) {
  const s = stateOf(body);
  if (s.mode !== 'preview') return;
  return request(body, { korean: s.korean, profile: profile ?? s.profile, lang: lang ?? s.lang });
}

export function undo(body) {
  const s = stateOf(body);
  if (s.saved) replaceUserNodes(body, s.saved);
  Object.assign(s, { mode: 'idle', saved: null, korean: null, shown: null, lang: 'auto', profile: 'email' });
  s.reqId++; // drop any result still in flight
  hideNote(s);
}

async function request(body, { korean, profile, lang }) {
  const s = stateOf(body);
  const prevMode = s.mode;
  const reqId = ++s.reqId;
  s.mode = 'translating';
  showNote(body, s, [span(profile === 'hard' ? 'Translating with Opus...' : 'Translating...')]);
  try {
    const root = document.querySelector('[role="main"]');
    const context = body.closest('[role="dialog"]') || !root ? [] : readThread(root, findViewerEmail(document));
    const r = await ask({ type: 'email', context, korean, profile, lang });
    if (reqId !== s.reqId || !body.isConnected) return;
    // The draft changed while translating (the user kept typing): never overwrite it.
    if (norm(nodesToText(userNodes(body))) !== norm(prevMode === 'preview' ? s.shown : korean)) {
      s.mode = prevMode;
      const parts = [span('The draft changed while translating, so the translation was dropped. Press Translate again.')];
      if (s.saved) parts.push(button('Undo', () => undo(body)));
      return showNote(body, s, parts, true);
    }
    const removed = replaceUserNodes(body, textToNodes(document, r.translation));
    if (prevMode !== 'preview') s.saved = removed; // first translation: keep the Korean nodes for Undo
    if (norm(nodesToText(userNodes(body))) !== norm(r.translation)) {
      replaceUserNodes(body, s.saved);
      Object.assign(s, { mode: 'idle', saved: null });
      return showNote(body, s, [span('Could not write the translation into the email. The Korean draft is back.')], true);
    }
    Object.assign(s, { mode: 'preview', korean, shown: r.translation, lang: r.lang, profile });
    showPreview(body, s, r);
  } catch (e) {
    if (reqId !== s.reqId) return;
    s.mode = prevMode;
    const parts = [span(`Translation failed: ${ERRORS[e.kind] || e.message}`)];
    if (s.saved) parts.push(button('Undo', () => undo(body)));
    showNote(body, s, parts, true);
  }
}
