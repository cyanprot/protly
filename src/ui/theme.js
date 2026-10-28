// Light or dark for protly's own UI, from the page's effective background. Popup and options use
// prefers-color-scheme instead (they have no page to match).

export function parseColor(css) {
  const m = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$/.exec((css || '').trim());
  if (!m) return null;
  const a = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : parseFloat(m[4]);
  return [Number(m[1]), Number(m[2]), Number(m[3]), a];
}

export function luminance([r, g, b]) {
  const lin = (c) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

export function pickTheme(doc) {
  const win = doc.defaultView;
  for (const el of [doc.body, doc.documentElement]) {
    if (!el || !win) continue;
    const c = parseColor(win.getComputedStyle(el).backgroundColor);
    if (c && c[3] > 0) return luminance(c) < 0.4 ? 'dark' : 'light';
  }
  return 'light';
}

const bound = new WeakMap(); // document -> Set of elements kept in sync

// Sets el.dataset.plTheme now and whenever html or body change class or style. Returns an unbind function.
// An element the page detached without unbinding (Gmail closing a compose window) is dropped on the next
// change, so it and its listeners are not kept alive; card.js and toast.js bind again when they re-insert.
export function bindTheme(el, doc = el.ownerDocument) {
  el.dataset.plTheme = pickTheme(doc);
  let set = bound.get(doc);
  if (!set) {
    set = new Set();
    bound.set(doc, set);
    const mo = new doc.defaultView.MutationObserver(() => {
      const t = pickTheme(doc);
      for (const e of set) {
        if (e.isConnected) e.dataset.plTheme = t;
        else set.delete(e);
      }
    });
    const opts = { attributes: true, attributeFilter: ['class', 'style'] };
    mo.observe(doc.documentElement, opts);
    if (doc.body) mo.observe(doc.body, opts);
  }
  set.add(el);
  return () => set.delete(el);
}
