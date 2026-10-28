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
  tr.className = `igt-tr igt-${mode}`;
  tr.textContent = translation;
  if (mode === 'replace') {
    tr.title = m.text ?? m.textEl.textContent;
    m.textEl.setAttribute('data-igt-hide', '');
  }
  m.textEl.after(tr);
}

export function clearTranslation(m) {
  m.textEl.removeAttribute('data-igt-hide');
  m.textEl.parentElement?.querySelectorAll(':scope > .igt-tr').forEach((n) => n.remove());
}

export function renderRetry(m, onClick) {
  clearTranslation(m);
  const b = m.textEl.ownerDocument.createElement('button');
  b.className = 'igt-tr igt-retry';
  b.textContent = '⟳';
  b.title = 'Translation failed, click to retry';
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  m.textEl.after(b);
}

export function setHoverOriginal(m, korean) {
  m.textEl.title = korean;
}

export function getComposerText(el) {
  return (el.innerText || '').replace(/\n$/, '');
}

export function setComposerText(el, text) {
  el.focus();
  el.ownerDocument.execCommand('selectAll', false);
  if (text) el.ownerDocument.execCommand('insertText', false, text);
  else el.ownerDocument.execCommand('delete', false);
}
