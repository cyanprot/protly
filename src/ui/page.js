import { TOKENS, BASE } from './tokens.css.js';
import { addFonts, FONT_FILES } from './fonts.js';

// Popup and options: the same tokens as the in-page components; light or dark follows the OS.
export function stylePage(doc = document) {
  const win = doc.defaultView;
  const sheet = (css) => { const s = new win.CSSStyleSheet(); s.replaceSync(css); return s; };
  doc.adoptedStyleSheets = [...doc.adoptedStyleSheets, sheet(TOKENS), sheet(BASE)];
  const root = doc.documentElement;
  root.classList.add('pl-root');
  // Extension pages load the bundled fonts by URL; no page CSP stands in the way here.
  addFonts(doc, { regular: chrome.runtime.getURL(FONT_FILES.regular), medium: chrome.runtime.getURL(FONT_FILES.medium) });
  const dark = win.matchMedia('(prefers-color-scheme: dark)');
  const apply = () => { root.dataset.plTheme = dark.matches ? 'dark' : 'light'; };
  apply();
  dark.addEventListener('change', apply);
}

// Message to the background; rejects with { kind } like the content scripts' ask().
export async function ask(msg) {
  const r = await chrome.runtime.sendMessage(msg);
  if (!r?.ok) {
    const e = new Error(r?.error?.message || 'no response');
    e.kind = r?.error?.kind;
    throw e;
  }
  return r.data;
}
