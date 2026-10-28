const TEXT_TYPES = new Set(['', 'text', 'search', 'email', 'url', 'tel']);
const MAX_DEPTH = 10;

// isContentEditable is the browser's answer; the [contenteditable] walk covers jsdom, which does not implement it.
function isEditable(el) {
  if (el?.isContentEditable === true) return true;
  const c = el?.closest?.('[contenteditable]');
  return !!c && c.getAttribute('contenteditable').toLowerCase() !== 'false';
}

// The focused element, through open shadow roots and same-origin iframes. Cross-origin frames give { el: null }.
export function deepActive(doc) {
  let d = doc;
  let el = d.activeElement;
  for (let i = 0; i < MAX_DEPTH && el; i++) {
    if (el.shadowRoot?.activeElement) { el = el.shadowRoot.activeElement; continue; }
    if (el.tagName !== 'IFRAME' && el.tagName !== 'FRAME') break;
    let inner = null;
    try { inner = el.contentDocument; } catch {}
    if (!inner) return { el: null, doc: d };
    d = inner;
    el = d.activeElement;
  }
  return { el, doc: d };
}

// 'text' | 'contenteditable' | null
export function classify(el) {
  if (!el || !el.tagName) return null;
  if (el.tagName === 'TEXTAREA') return el.readOnly || el.disabled ? null : 'text';
  if (el.tagName === 'INPUT') {
    const type = (el.getAttribute('type') || '').toLowerCase();
    return TEXT_TYPES.has(type) && !el.readOnly && !el.disabled ? 'text' : null;
  }
  return isEditable(el) ? 'contenteditable' : null;
}

function editableRoot(el) {
  let r = el;
  while (r.parentElement && isEditable(r.parentElement)) r = r.parentElement;
  return r;
}

// { el, doc, kind } for the focused text box, or null.
export function findTarget(doc) {
  const { el, doc: d } = deepActive(doc);
  const kind = classify(el);
  if (!kind) return null;
  return { el: kind === 'contenteditable' ? editableRoot(el) : el, doc: d, kind };
}

// The page selection, preferring the focused frame. rect() re-reads the range so a card follows scrolling.
export function selectionInfo(doc) {
  const { doc: inner } = deepActive(doc);
  for (const d of inner === doc ? [doc] : [inner, doc]) {
    const sel = d.getSelection?.();
    const text = sel ? sel.toString() : '';
    if (!text.trim()) continue;
    const range = sel.getRangeAt(0).cloneRange();
    return { doc: d, text, rect: () => { try { return range.getBoundingClientRect(); } catch { return null; } } };
  }
  return { doc, text: '', rect: () => null };
}
