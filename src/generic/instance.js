import { addFonts } from '../ui/fonts.js';
import { createCard } from '../ui/card.js';
import { showToast } from '../ui/toast.js';
import { errorText, GLOBAL_KINDS } from '../ui/errors.js';
import { commitByRefocus, nextFrame, settleComposition } from '../lib/ime.js';
import { decideBox, decideSelection } from './decide.js';
import { deepActive, findTarget, selectionInfo } from './target.js';
import { boxHolds, readBox, writeBox } from './writer.js';

const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
const NOTHING = 'Put the cursor in a text box or select text.';
const BLOCKED = 'protly cannot reach this frame. Right-click inside the box instead.';
const MAX_CHARS = 8000;
const TOO_LONG = `Too long for protly (over ${MAX_CHARS} characters).`;
const FOCUS_MOVED = 'Focus moved, so the translation was not written.';
const CORNER = { top: 16, bottom: 16, left: 16, right: 16, width: 0, height: 0, x: 16, y: 16 };

export async function defaultAsk(msg) {
  let r;
  try {
    r = await chrome.runtime.sendMessage(msg);
  } catch (err) {
    const e = new Error(err?.message || String(err));
    e.kind = /context invalidated|Receiving end does not exist/i.test(e.message) ? 'stale' : 'internal';
    throw e;
  }
  if (!r?.ok) { const e = new Error(r?.error?.message || 'no response'); e.kind = r?.error?.kind; throw e; }
  return r.data;
}

// One per isolated world (run.js keeps it on globalThis.__protly): one card, one set of listeners per document.
export function createInstance({ doc: top = document, fonts = null, ask = defaultAsk, hostname } = {}) {
  const host = () => hostname || top.defaultView?.location?.hostname || '';
  // box: { t, d, card, mode: 'idle'|'working'|'preview', original, shown, lang, hard, reqId, last }
  let box = null;
  let pop = null; // selection popover card
  let seq = 0;
  let composing = false;
  let starting = false; // doBox is reading the box: a second Alt+T must not send a second request
  const wired = new WeakSet();

  const toast = (text, opts = {}) => showToast(text, { doc: top, transient: true, ...opts });

  function wire(doc) {
    if (wired.has(doc)) return;
    wired.add(doc);
    if (fonts) addFonts(doc, fonts);
    doc.addEventListener('compositionstart', () => { composing = true; }, true);
    doc.addEventListener('compositionend', () => { composing = false; }, true);
    doc.addEventListener('keydown', onKeyDown, true);
    doc.addEventListener('focusin', onFocusIn, true);
  }

  // composedPath: a box inside a shadow root shows up on document listeners as its shadow host.
  const inBox = (cur, e) => { const p = e.composedPath?.() ?? [e.target]; return p.includes(cur.t.el) || p.includes(cur.card.host); };

  // Focus is in the box, or in the card (its language chip).
  function holdsFocus(cur, card = false) {
    const a = deepActive(top).el;
    if (!a) return false;
    if (a === cur.t.el || cur.t.el.contains(a)) return true;
    return card && (a === cur.card.host || a.getRootNode?.() === cur.card.host.shadowRoot);
  }

  function onKeyDown(e) {
    if (e.key !== 'Escape' || e.isComposing) return;
    if (box && (box.mode === 'preview' || box.mode === 'working') && inBox(box, e)) {
      e.preventDefault();
      e.stopImmediatePropagation();
      if (box.mode === 'working') cancel(box); else undo();
      return;
    }
    if (pop) { pop.hide(); pop = null; } // the page still gets its Esc
  }

  // Focus moved elsewhere: the preview is accepted as it is and the card closes.
  function onFocusIn(e) {
    if (box?.mode === 'preview' && !inBox(box, e)) close();
  }

  // A click on plain text fires no focusin, so blur closes too. Checked a tick later, when focus has landed:
  // into the card's chip keeps it open, and so does the window losing focus (the box stays the active element).
  function onFocusOut() {
    const cur = box;
    if (cur?.mode !== 'preview') return;
    setTimeout(() => { if (box === cur && cur.mode === 'preview' && !holdsFocus(cur, true)) close(); }, 0);
  }

  function close() {
    if (!box) return;
    box.reqId = 0;
    box.card.hide();
    box.t.el.removeEventListener('focusout', onFocusOut);
    box.card.host.removeEventListener('focusout', onFocusOut);
    box = null;
  }

  // Over a modal dialog or a fullscreen element the card must live inside it to be seen and clicked.
  function lift(cur) {
    const layer = cur.t.el.closest?.('dialog[open]') || cur.t.doc.fullscreenElement;
    if (layer && cur.card.host.parentNode !== layer) layer.appendChild(cur.card.host);
  }

  const actionsFor = (cur) => (cur.mode === 'preview'
    ? [{ label: 'Opus', onClick: () => rerun({ hard: true }) }, { label: 'Undo', onClick: () => undo() }]
    : [{ label: 'Close', onClick: () => close() }]);

  function showPreview(cur) {
    const polish = cur.d.kind === 'polish';
    cur.card.preview({
      text: cur.last.back_translation,
      model: cur.last.model, // the card turns the id into 'Sonnet' or 'Opus'
      ...(polish ? {} : { lang: cur.lang, onLang: (code) => rerun({ lang: code }) }),
      actions: actionsFor(cur),
      hints: 'Esc undo',
    });
  }

  function showError(cur, e) {
    const text = errorText(e);
    cur.card.message(text, { error: true, actions: actionsFor(cur) });
    if (GLOBAL_KINDS.has(e?.kind)) showToast(text, { doc: top, error: true });
  }

  function cancel(cur) {
    if (box !== cur || cur.mode !== 'working') return;
    cur.reqId = 0; // the result, when it arrives, is dropped
    cur.mode = cur.prev;
    if (cur.mode === 'preview') showPreview(cur); else close();
  }

  async function request(cur) {
    const reqId = ++seq;
    cur.reqId = reqId;
    cur.prev = cur.mode;
    cur.mode = 'working';
    const polish = cur.d.kind === 'polish';
    cur.card.working(`${polish ? 'Polishing' : 'Translating'}${cur.hard ? ' with Opus' : ''}`, { onCancel: () => cancel(cur) });
    lift(cur);
    const before = readBox(cur.t); // what the box must still hold when the result lands
    const live = () => box === cur && cur.reqId === reqId;
    let r;
    try {
      r = polish
        ? await ask({ type: 'polish', text: cur.d.text, profile: cur.hard ? 'hard' : 'polish' })
        : await ask({ type: 'box', text: cur.d.text, lang: cur.lang, profile: cur.hard ? 'hard' : 'outgoing', hostname: host() });
    } catch (e) {
      if (!live()) return;
      cur.mode = cur.prev;
      showError(cur, e);
      return;
    }
    if (!live()) return;
    if (norm(readBox(cur.t)) !== norm(before)) {
      cur.mode = cur.prev;
      cur.card.message('The text changed while translating, so the result was dropped.', { error: true, actions: actionsFor(cur) });
      return;
    }
    if (composing) await settleComposition(cur.t.el, { composing: true }); // never write into an open composition
    if (!live()) return;
    if (norm(readBox(cur.t)) !== norm(before)) { // the composition committed more text
      cur.mode = cur.prev;
      cur.card.message('The draft changed, so nothing was changed.', { error: true, actions: actionsFor(cur) });
      return;
    }
    // contenteditable needs focus to write; never pull it back from where the user went
    const focusOk = () => cur.t.kind === 'text' || holdsFocus(cur);
    const focusMoved = () => { close(); toast(FOCUS_MOVED); };
    if (!focusOk()) { focusMoved(); return; }
    const w = await writeBox(cur.t, r.translation, { stillOk: () => live() && focusOk() });
    if (w === null) { if (live()) focusMoved(); return; } // Esc or a focus change during the select settle
    if (!w) {
      const back = (await boxHolds(cur.t, before)) || (await writeBox(cur.t, before));
      cur.mode = cur.prev;
      cur.card.message(back
        ? 'Could not write into this box. Nothing was changed.'
        : 'Could not write into this box. Check the text: Ctrl+Z may bring it back.', { error: true, actions: actionsFor(cur) });
      return;
    }
    if (!live()) { // Esc landed while the write was verified: put the text back
      if (holdsFocus(cur)) await writeBox(cur.t, before);
      return;
    }
    Object.assign(cur, { mode: 'preview', shown: r.translation, last: r, lang: polish ? null : (r.lang ?? cur.lang) });
    showPreview(cur);
  }

  async function rerun({ hard = box?.hard, lang = box?.lang, force = false } = {}) {
    const cur = box;
    if (!cur || cur.mode !== 'preview') return;
    if (!force && norm(readBox(cur.t)) !== norm(cur.shown)) {
      cur.card.message('You edited the text. Running again replaces your edit.', {
        actions: [
          { label: 'Replace anyway', onClick: () => rerun({ hard, lang, force: true }) },
          { label: 'Keep my edit', onClick: () => showPreview(cur) },
          { label: 'Undo', onClick: () => undo() },
        ],
      });
      return;
    }
    Object.assign(cur, { hard, lang });
    await request(cur);
  }

  async function undo() {
    const cur = box;
    if (!cur) return;
    close();
    if (norm(readBox(cur.t)) !== norm(cur.original) && !(await writeBox(cur.t, cur.original))) {
      toast('Could not restore the original text. Ctrl+Z may bring it back.', { error: true });
    }
  }

  async function doBox(t) {
    let cur;
    starting = true;
    try {
      wire(t.doc);
      commitByRefocus(t.el); // injected after the fact: commit any open composition before reading
      await nextFrame();
      const original = readBox(t);
      if (original.length > MAX_CHARS) { toast(TOO_LONG); return; }
      const d = decideBox(original);
      if (d.kind === 'none') { toast('Nothing to translate or polish in this box.'); return; }
      close();
      const card = createCard({ doc: t.doc, place: { float: () => t.el.getBoundingClientRect() } });
      box = cur = { t, d, card, mode: 'idle', prev: 'idle', original, shown: null, lang: d.lang ?? null, hard: false, reqId: 0, last: null };
      t.el.addEventListener('focusout', onFocusOut);
      card.host.addEventListener('focusout', onFocusOut);
    } finally {
      starting = false;
    }
    await request(cur);
  }

  async function doSelection(text, sel) {
    if (text.length > MAX_CHARS) { toast(TOO_LONG); return; }
    const kind = decideSelection(text);
    if (kind === 'already-ko') { toast('Already Korean.'); return; }
    if (kind === 'none') { toast(NOTHING); return; }
    const doc = sel?.text.trim() ? sel.doc : top;
    wire(doc);
    pop?.hide();
    const at = () => { const r = sel?.rect(); return r && (r.width || r.height) ? r : CORNER; };
    const card = createCard({ doc, place: { float: at } });
    pop = card;
    const done = () => { card.hide(); if (pop === card) pop = null; };
    card.working('Translating', { onCancel: done });
    try {
      const r = await ask({ type: 'selection', text });
      if (pop !== card) return;
      card.message(r.translation, {
        actions: [{ label: 'Close', onClick: done }], // the text is selectable; no Copy button
      });
    } catch (e) {
      if (pop !== card) return;
      card.message(errorText(e), { error: true, actions: [{ label: 'Close', onClick: done }] });
      if (GLOBAL_KINDS.has(e?.kind)) showToast(errorText(e), { doc: top, error: true });
    }
  }

  // args: { source: 'command' | 'menu-selection' | 'menu-editable', selectionText? }
  async function run(args = {}) {
    try {
      wire(top);
      if (args.source === 'menu-selection') {
        const sel = selectionInfo(top);
        await doSelection(args.selectionText || sel.text, sel);
        return;
      }
      if (starting) return;
      const t = findTarget(top);
      if (!t && deepActive(top).blocked) { toast(BLOCKED); return; } // focus is in a cross-origin frame
      const sel = t ? null : selectionInfo(top);
      const selOutside = !!sel?.text.trim() && !(box && sel.node && box.t.el.contains(sel.node));
      const same = box && (t ? t.el === box.t.el : !selOutside);
      if (same && box.mode === 'working') return; // one request at a time
      // menu-editable too: re-polishing the shown translation would lose the original for Undo
      if (same && box.mode === 'preview') { await rerun({ hard: true }); return; }
      if (t) { await doBox(t); return; }
      if (selOutside) { await doSelection(sel.text, sel); return; }
      toast(NOTHING);
    } catch (e) {
      console.warn('[protly] run failed', e);
      toast(errorText(e), { error: true });
    }
  }

  return { run, toast: (text) => showToast(text, { doc: top, error: true }) };
}
