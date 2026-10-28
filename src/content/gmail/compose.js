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
const MOUNT_GRACE_MS = 3000; // Gmail can render a body before its toolbar
const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');
const states = new WeakMap(); // compose body -> state; dropped with the compose
let badgeSet = false;
let viewerWarned = false;

async function ask(msg) {
  let r;
  try {
    r = await chrome.runtime.sendMessage(msg);
  } catch (err) {
    const e = new Error(/context invalidated/i.test(err?.message) ? 'ig-translate was reloaded. Reload this tab.' : err?.message || String(err));
    e.kind = 'internal';
    throw e;
  }
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
}

function stateOf(body) {
  let s = states.get(body);
  if (!s) {
    s = {
      mode: 'idle', reqId: 0, saved: null, korean: null, shown: null, lang: 'auto', profile: 'email',
      last: null, note: null, anchor: null, btn: null, firstMiss: 0, warned: false,
    };
    states.set(body, s);
  }
  return s;
}

function setBadge(on) {
  if (badgeSet === on) return;
  badgeSet = on;
  ask({ type: 'badge', text: on ? '!' : '' }).catch(() => {});
}

// Called on every scan; (re)mounts the button until it is in place next to this compose's own Send.
export function mountCompose(body) {
  const s = stateOf(body);
  if (s.btn?.isConnected) return;
  const sendCell = composeOf(body)?.querySelector(GSEL.send)?.closest('td');
  if (!sendCell) {
    s.firstMiss ||= Date.now();
    if (!s.warned && Date.now() - s.firstMiss > MOUNT_GRACE_MS) {
      s.warned = true;
      console.warn('[igt] Gmail Send button not found; Translate button not mounted (Alt+T still works)');
      setBadge(true);
    }
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
  s.btn = btn;
  if (s.warned) { s.warned = false; setBadge(false); }
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

const previewControls = (body, s) => [
  langPicker(body, s.lang),
  button('Opus', () => retranslate(body, { profile: 'hard' })),
  button('Undo', () => undo(body)),
];

function showPreview(body, s) {
  showNote(body, s, [span(`${s.last.back_translation}  · ${modelLabel(s.last.model)}`), ...previewControls(body, s)]);
}

// An error note that keeps the preview controls when there is a preview to go back to.
function showError(body, s, message) {
  showNote(body, s, [span(message), ...(s.mode === 'preview' ? previewControls(body, s) : [])], true);
}

// Translate button and Alt+T.
export function translate(body) {
  const s = stateOf(body);
  if (s.mode === 'translating') return;
  const nodes = userNodes(body);
  const text = nodesToText(nodes).trim();
  if (s.mode === 'preview') {
    if (norm(text) === norm(s.shown)) return; // nothing new to translate
    if (!hasHangul(text)) return showError(body, s, 'No Korean text to translate. Use the picker or Opus to translate the original again.');
    // A new Korean draft replaced the preview. The body holds it, so the older Korean is not needed for Undo.
    Object.assign(s, { mode: 'idle', saved: null });
  }
  if (!hasHangul(text)) return showNote(body, s, [span('No Korean text to translate.')], true);
  if (hasMedia(nodes)) return showNote(body, s, [span('The draft contains images. Translate the text before adding images.')], true);
  return request(body, { korean: text, profile: 'email', lang: 'auto' });
}

// Picker and Opus in preview: same Korean, other language or model.
function retranslate(body, { lang, profile, force = false }) {
  const s = stateOf(body);
  if (s.mode !== 'preview') return;
  const opts = { korean: s.korean, profile: profile ?? s.profile, lang: lang ?? s.lang };
  if (!force && norm(nodesToText(userNodes(body))) !== norm(s.shown)) {
    return showNote(body, s, [
      span('You edited the translation. Translating again replaces your edit.'),
      button('Replace anyway', () => retranslate(body, { ...opts, force: true })),
      button('Keep my edit', () => showPreview(body, s)),
      button('Undo', () => undo(body)),
    ]);
  }
  return request(body, opts);
}

export function undo(body) {
  const s = stateOf(body);
  if (s.saved) replaceUserNodes(body, s.saved);
  Object.assign(s, { mode: 'idle', saved: null, korean: null, shown: null, lang: 'auto', profile: 'email', last: null });
  s.reqId++; // drop any result still in flight
  hideNote(s);
}

function cancel(body, reqId, prevMode) {
  const s = stateOf(body);
  if (s.reqId !== reqId || s.mode !== 'translating') return;
  s.reqId++; // the result, when it arrives, is dropped
  s.mode = prevMode;
  if (prevMode === 'preview') showPreview(body, s); else hideNote(s);
}

async function request(body, { korean, profile, lang }) {
  const s = stateOf(body);
  const prevMode = s.mode;
  const expected = nodesToText(userNodes(body)); // what the body must still hold when the result lands
  const reqId = ++s.reqId;
  s.mode = 'translating';
  showNote(body, s, [
    span(profile === 'hard' ? 'Translating with Opus...' : 'Translating...'),
    button('Cancel', () => cancel(body, reqId, prevMode)),
  ]);
  try {
    const root = document.querySelector('[role="main"]');
    let context = [];
    if (!body.closest('[role="dialog"]') && root) {
      const viewer = findViewerEmail(document);
      if (!viewer && !viewerWarned) {
        viewerWarned = true;
        console.warn('[igt] Gmail account email not found; every thread message counts as from the other side');
      }
      context = readThread(root, viewer);
    }
    const r = await ask({ type: 'email', context, korean, profile, lang });
    if (reqId !== s.reqId || !body.isConnected) return;
    s.mode = prevMode;
    // The draft changed while translating (the user kept typing): never overwrite it.
    if (norm(nodesToText(userNodes(body))) !== norm(expected)) {
      return showError(body, s, 'The draft changed while translating, so the translation was dropped.');
    }
    const removed = replaceUserNodes(body, textToNodes(document, r.translation));
    if (norm(nodesToText(userNodes(body))) !== norm(r.translation)) {
      replaceUserNodes(body, removed);
      return showError(body, s, 'Could not write the translation into the email. Your draft is back as it was.');
    }
    if (prevMode !== 'preview') s.saved = removed; // first translation: keep the Korean nodes for Undo
    Object.assign(s, { mode: 'preview', korean, shown: r.translation, lang: r.lang, profile, last: r });
    showPreview(body, s);
  } catch (e) {
    if (reqId !== s.reqId) return;
    s.mode = prevMode;
    showError(body, s, `Translation failed: ${ERRORS[e.kind] || e.message}`);
  }
}
