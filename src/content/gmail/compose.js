import { GSEL, composeOf, findViewerEmail } from './selectors.js';
import { userNodes, nodesToText, textToNodes, replaceUserNodes, hasMedia } from './body.js';
import { readThread } from './thread.js';
import { hasHangul, parseLangPrefix } from '../../lib/lang.js';
import { createCard } from '../../ui/card.js';
import { ERRORS, errorText } from '../../ui/errors.js';
import { trusted } from '../../ui/trust.js';

const MOUNT_GRACE_MS = 3000; // Gmail can render a body before its toolbar
const HINTS = 'Esc undo';
const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
// The user changed the translation in the body since the preview appeared.
const edited = (body, s) => norm(nodesToText(userNodes(body))) !== norm(s.shown);
const states = new WeakMap(); // compose body -> state; dropped with the compose
let badgeSet = false;
let viewerWarned = false;

async function ask(msg) {
  let r;
  try {
    r = await chrome.runtime.sendMessage(msg);
  } catch (err) {
    // Same detection as the Instagram ask(): a reloaded or updated extension.
    const stale = /context invalidated|Receiving end does not exist/i.test(err?.message);
    const e = new Error(stale ? ERRORS.stale : err?.message || String(err));
    e.kind = stale ? 'stale' : 'internal';
    throw e;
  }
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
}

function stateOf(body) {
  let s = states.get(body);
  if (!s) {
    // korean is the source text: the Korean draft, or the English draft being polished (kind 'polish').
    s = {
      mode: 'idle', reqId: 0, saved: null, kind: 'translate', korean: null, shown: null, lang: 'auto', profile: 'email',
      last: null, card: null, cardAnchor: null, anchor: null, btn: null, firstMiss: 0, warned: false,
    };
    states.set(body, s);
  }
  return s;
}

function setBadge(on) {
  if (badgeSet === on) return;
  badgeSet = on;
  ask({ type: 'badge', text: on ? '!' : '', reason: on ? 'Gmail Send button not found' : '' }).catch(() => {});
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
      console.warn('[protly] Gmail Send button not found; Translate button not mounted (Alt+T still works)');
      setBadge(true);
    }
    return;
  }
  s.anchor = sendCell.closest('table');
  const td = document.createElement('td');
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'pl-g-btn';
  btn.textContent = 'Translate';
  btn.title = 'Translate the Korean draft, or polish an English one (Alt+T)';
  btn.addEventListener('click', (e) => { if (trusted(e)) translate(body); }); // a page script's click is not the user's
  td.appendChild(btn);
  sendCell.after(td);
  s.btn = btn;
  if (s.warned) { s.warned = false; setBadge(false); }
}

// One card per compose, above its toolbar table; rebuilt when Gmail replaces the toolbar.
function cardOf(body, s) {
  const anchor = s.anchor?.isConnected ? s.anchor : null;
  if (!s.card || s.cardAnchor !== anchor) {
    s.card?.hide();
    s.card = createCard({ place: anchor ? { before: anchor } : { after: body } });
    s.cardAnchor = anchor;
  }
  return s.card;
}

const act = (label, onClick) => ({ label, onClick });
// A polish preview has no target language, so no picker.
// The chip takes focus and the working card removes it, so give focus back to the body for the next Esc.
const pickerOf = (body, s) => (s.kind === 'polish' ? {} : {
  lang: s.lang, onLang: (lang) => { body.focus(); retranslate(body, { lang }); },
});
const previewActions = (body) => [act('Opus', () => retranslate(body, { profile: 'hard' })), act('Undo', () => undo(body))];

function say(body, s, text, { error = false, actions = [], picker = false } = {}) {
  cardOf(body, s).message(text, { error, actions, ...(picker ? pickerOf(body, s) : {}) });
}

function hideNote(s) {
  s.card?.hide();
}

function showPreview(body, s) {
  cardOf(body, s).preview({
    text: s.last.back_translation, model: s.last.model, ...pickerOf(body, s), actions: previewActions(body), hints: HINTS,
  });
}

// An error that keeps the preview controls when there is a preview to go back to.
function showError(body, s, message) {
  const inPreview = s.mode === 'preview';
  say(body, s, message, { error: true, actions: inPreview ? previewActions(body) : [], picker: inPreview });
}

// Translate button and Alt+T (through the background command).
export function translate(body) {
  const s = stateOf(body);
  if (s.mode === 'translating') return;
  const nodes = userNodes(body);
  const text = nodesToText(nodes).trim();
  if (s.mode === 'preview') {
    if (norm(text) === norm(s.shown)) return; // nothing new to translate
    // Polish only starts from idle, so Undo always goes back to the original draft.
    if (!hasHangul(text)) return showError(body, s, 'No Korean text to translate. To polish this English, press Undo first.');
    // A new Korean draft replaced the preview. The body holds it, so the older Korean is not needed for Undo.
    Object.assign(s, { mode: 'idle', saved: null });
  }
  let opts;
  if (hasHangul(text)) {
    // The prefix ("ru: ...") is a one-off override; the saved nodes keep it, so Undo brings it back.
    const p = parseLangPrefix(text);
    opts = { kind: 'translate', korean: p.text, profile: 'email', lang: p.lang ?? 'auto' };
  } else if (/\p{L}/u.test(text)) {
    // Explicit action (button or Alt+T): polish always. The popup toggle only governs Enter on Instagram.
    opts = { kind: 'polish', korean: text, profile: 'email' };
  } else {
    return say(body, s, 'Nothing to translate or polish.', { error: true });
  }
  if (hasMedia(nodes)) {
    const verb = opts.kind === 'polish' ? 'Polish' : 'Translate';
    return say(body, s, `The draft contains images. ${verb} the text before adding images.`, { error: true });
  }
  return request(body, opts);
}

// Picker and Opus in preview: same source and kind, other language or model.
function retranslate(body, { lang, profile, force = false }) {
  const s = stateOf(body);
  if (s.mode !== 'preview') return;
  const opts = { kind: s.kind, korean: s.korean, profile: profile ?? s.profile, lang: lang ?? s.lang };
  if (!force && edited(body, s)) {
    return say(body, s, 'You edited the translation. Translating again replaces your edit.', {
      actions: [
        act('Replace anyway', () => retranslate(body, { ...opts, force: true })),
        act('Keep my edit', () => showPreview(body, s)),
        act('Undo', () => undo(body)),
      ],
    });
  }
  return request(body, opts);
}

export function undo(body) {
  const s = stateOf(body);
  if (s.saved) replaceUserNodes(body, s.saved);
  Object.assign(s, { mode: 'idle', saved: null, kind: 'translate', korean: null, shown: null, lang: 'auto', profile: 'email', last: null });
  s.reqId++; // drop any result still in flight
  hideNote(s);
}

// Esc in a compose body: undo a preview or a translation in flight. False when there is nothing to undo.
// An edited translation is never undone by Esc (the DOM swap is outside Ctrl+Z): retranslate's
// edited-translation prompt asks instead, with Undo as one of its choices.
export function escape(body) {
  const s = states.get(body);
  if (!s || s.mode === 'idle') return false;
  if (s.mode === 'preview' && edited(body, s)) {
    retranslate(body, {});
    return true;
  }
  undo(body);
  return true;
}

function cancel(body, reqId, prevMode) {
  const s = stateOf(body);
  if (s.reqId !== reqId || s.mode !== 'translating') return;
  s.reqId++; // the result, when it arrives, is dropped
  s.mode = prevMode;
  if (prevMode === 'preview') showPreview(body, s); else hideNote(s);
}

// The thread for an inline reply; a new compose window has none.
function threadContext(body) {
  const root = document.querySelector('[role="main"]');
  if (body.closest('[role="dialog"]') || !root) return [];
  const viewer = findViewerEmail(document);
  if (!viewer && !viewerWarned) {
    viewerWarned = true;
    console.warn('[protly] Gmail account email not found; every thread message counts as from the other side');
  }
  return readThread(root, viewer);
}

async function request(body, { kind = 'translate', korean, profile, lang }) {
  const s = stateOf(body);
  const prevMode = s.mode;
  const expected = nodesToText(userNodes(body)); // what the body must still hold when the result lands
  const reqId = ++s.reqId;
  s.mode = 'translating';
  const polish = kind === 'polish';
  const verb = polish ? 'Polishing' : 'Translating';
  cardOf(body, s).working(profile === 'hard' ? `${verb} with Opus` : verb, { onCancel: () => cancel(body, reqId, prevMode) });
  try {
    // Polish takes no thread context: one draft does not need it.
    const r = polish
      ? await ask({ type: 'polish', text: korean, profile })
      : await ask({ type: 'email', context: threadContext(body), korean, profile, lang });
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
    if (prevMode !== 'preview') s.saved = removed; // first result: keep the original draft nodes for Undo
    // The polish result carries no lang, so keep the current one.
    Object.assign(s, { mode: 'preview', kind, korean, shown: r.translation, lang: r.lang ?? s.lang, profile, last: r });
    showPreview(body, s);
  } catch (e) {
    if (reqId !== s.reqId) return;
    s.mode = prevMode;
    showError(body, s, `${polish ? 'Polish' : 'Translation'} failed: ${errorText(e)}`);
  }
}
