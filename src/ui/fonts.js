// Chrome ignores @font-face inside shadow roots, but a FontFace added to document.fonts is visible to them.
export const FONT_FILES = {
  regular: 'src/ui/fonts/protly-mono-400.woff2',
  medium: 'src/ui/fonts/protly-mono-500.woff2',
};

const done = new WeakSet();

// regular / medium: a URL string or the font bytes (ArrayBuffer or Uint8Array).
export function addFonts(doc, { regular, medium }) {
  if (!doc.fonts || done.has(doc)) return; // jsdom has no doc.fonts
  done.add(doc);
  const FontFaceImpl = doc.defaultView?.FontFace ?? globalThis.FontFace;
  for (const [src, weight] of [[regular, '400'], [medium, '500']]) {
    if (!src) continue;
    const face = new FontFaceImpl('protly-mono', typeof src === 'string' ? `url("${src}")` : src,
      { weight, style: 'normal', display: 'swap' });
    doc.fonts.add(face);
    face.load().catch(() => {}); // a failed load leaves the monospace fallback
  }
}

// Instagram and Gmail: the bundled files as bytes, read by the content script, never by the page (CSP font-src).
export async function fetchFonts(getURL, fetchImpl = fetch) {
  const get = async (path) => {
    const r = await fetchImpl(getURL(path));
    if (!r.ok) throw new Error(`font ${path}: HTTP ${r.status}`);
    return r.arrayBuffer();
  };
  const [regular, medium] = await Promise.all([get(FONT_FILES.regular), get(FONT_FILES.medium)]);
  return { regular, medium };
}
