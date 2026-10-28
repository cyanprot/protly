import { SEL, senderOf, findViewerName } from './selectors.js';

export const findThreadRoot = (doc) => doc.querySelector(SEL.threadRoot);
export const findComposer = (doc) => doc.querySelector(SEL.composer);

// Text bubbles only, top to bottom. Rows without a text element (media, stickers) are skipped.
// viewer defaults to the live page's sidebar username; tests pass it explicitly.
export function readMessages(root, viewer = findViewerName(root.ownerDocument)) {
  const out = [];
  for (const row of root.querySelectorAll(SEL.messageRow)) {
    const textEl = row.querySelector(SEL.messageText);
    const text = textEl?.innerText ?? textEl?.textContent ?? '';
    if (!text.trim()) continue;
    out.push({ row, textEl, text: text.trim(), from: senderOf(row, viewer) });
  }
  return out;
}

// We never change text inside Instagram's own nodes: React may re-render and throw.
// We hide the original via a data attribute (React leaves unknown attributes alone) and add a sibling.
export function renderTranslation(m, translation, mode) {
  clearTranslation(m);
  const tr = m.textEl.ownerDocument.createElement('div');
  tr.className = `pl-tr pl-${mode}`;
  tr.textContent = translation;
  if (mode === 'replace') {
    tr.title = m.text ?? m.textEl.textContent;
    m.textEl.setAttribute('data-pl-hide', '');
  }
  m.textEl.after(tr);
}

export function clearTranslation(m) {
  m.textEl.removeAttribute('data-pl-hide');
  if (m.textEl.hasAttribute('data-pl-title')) {
    m.textEl.removeAttribute('title');
    m.textEl.removeAttribute('data-pl-title');
  }
  m.textEl.parentElement?.querySelectorAll(':scope > .pl-tr').forEach((n) => n.remove());
}

// Instagram reuses message nodes across threads, so everything we added must go on teardown.
export function clearAllTranslations(root) {
  root.querySelectorAll('.pl-tr').forEach((n) => n.remove());
  root.querySelectorAll('[data-pl-hide]').forEach((n) => n.removeAttribute('data-pl-hide'));
  root.querySelectorAll('[data-pl-title]').forEach((n) => { n.removeAttribute('title'); n.removeAttribute('data-pl-title'); });
}

// True while the row still shows the text it was read with (nodes get reused for other messages).
export function stillShows(m) {
  const el = m.textEl;
  return el.isConnected && (el.innerText ?? el.textContent ?? '').trim() === m.text;
}

export function renderRetry(m, onClick) {
  clearTranslation(m);
  const b = m.textEl.ownerDocument.createElement('button');
  b.className = 'pl-tr pl-retry';
  b.textContent = '⟳';
  b.title = 'Translation failed, click to retry';
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  m.textEl.after(b);
}

export function setHoverOriginal(m, korean) {
  m.textEl.title = korean;
  m.textEl.setAttribute('data-pl-title', '');
}

export function getComposerText(el) {
  return (el.innerText || '').replace(/\n$/, '');
}

// Lexical syncs its selection on `selectionchange`, so it needs a moment between selecting and inserting,
// otherwise insertText is dropped (spike-notes, Composer write). Clearing to empty is not supported by Lexical
// via execCommand; callers only write non-empty text.
export const SELECT_SETTLE_MS = 60;
// stillOk() is re-checked after the settle; false aborts the insert (thread switched, write superseded).
// Returns true when the text was inserted.
export async function setComposerText(el, text, stillOk = () => true) {
  el.focus();
  el.ownerDocument.getSelection().selectAllChildren(el);
  await new Promise((r) => setTimeout(r, SELECT_SETTLE_MS));
  if (!el.isConnected || !stillOk()) return false;
  el.focus();
  el.ownerDocument.execCommand('insertText', false, text);
  return true;
}
