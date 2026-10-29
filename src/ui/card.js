import { TOKENS, BASE } from './tokens.css.js';
import { CARD_CSS } from './card.css.js';
import { bindTheme } from './theme.js';
import { LANG_NAMES, langName } from '../lib/lang.js';

export const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');

const GAP = 6; // px between the anchor rect and a floating card
const shadows = new WeakMap(); // card host -> its closed shadow root

// The card's shadow root is closed, so page scripts cannot read its text or click its buttons; protly code (and
// tests) reach it through this module's own handle.
export const shadowOf = (host) => shadows.get(host) ?? null;

// place: { before: Element } | { after: Element } | { float: () => DOMRect }. See the plan's shared contracts.
export function createCard({ doc = document, place }) {
  const win = doc.defaultView;
  const host = doc.createElement('div');
  host.className = 'pl-card';
  const shadow = host.attachShadow({ mode: 'closed' });
  shadows.set(host, shadow);
  const style = doc.createElement('style');
  style.textContent = TOKENS + BASE + CARD_CSS;
  const root = doc.createElement('div');
  root.className = 'pl-root';
  root.setAttribute('role', 'status');
  root.setAttribute('aria-live', 'polite');
  shadow.append(style, root);
  let unbindTheme = null;

  const el = (tag, cls, text) => {
    const e = doc.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const button = ({ label, onClick }) => {
    const b = el('button', null, label);
    b.type = 'button';
    b.addEventListener('mousedown', (e) => e.preventDefault()); // keep focus in the composer or text box
    b.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); onClick(e); });
    return b;
  };
  const chip = (lang, onLang) => {
    const sel = el('select', 'pl-chip');
    sel.title = 'Change target language';
    const codes = Object.keys(LANG_NAMES).filter((c) => c !== 'ko');
    if (!codes.includes(lang)) codes.unshift(lang); // a partner language outside the list
    for (const c of codes) {
      const o = el('option', null, langName(c));
      o.value = c;
      sel.appendChild(o);
    }
    sel.value = lang;
    sel.addEventListener('change', () => onLang(sel.value));
    return sel;
  };

  function placeFloat() {
    if (!host.isConnected) { api.hide(); return; } // the page removed it without hide(): drop the listeners
    const r = place.float();
    const box = host.getBoundingClientRect();
    const h = box.height || 0;
    const w = box.width || 0;
    const below = r.bottom + GAP;
    const top = below + h > win.innerHeight && r.top - GAP - h >= 0 ? r.top - GAP - h : below;
    const left = Math.max(GAP, Math.min(r.left, win.innerWidth - w - GAP));
    host.style.top = `${Math.round(top)}px`;
    host.style.left = `${Math.round(left)}px`;
  }

  function insert() {
    if (host.isConnected) return;
    if (place.before) place.before.before(host);
    else if (place.after) place.after.after(host);
    else {
      host.style.position = 'fixed';
      host.style.zIndex = '2147483646';
      (doc.body || doc.documentElement).appendChild(host);
      win.addEventListener('scroll', placeFloat, true);
      win.addEventListener('resize', placeFloat);
    }
    if (!place.float) host.style.display = 'block';
    unbindTheme = bindTheme(root, doc);
  }

  function render(nodes, { error = false } = {}) {
    insert();
    root.classList.toggle('err', error);
    root.replaceChildren(...nodes);
    if (place.float) placeFloat();
  }

  const trailing = (lang, onLang, actions, hints) => [
    ...(lang && onLang ? [chip(lang, onLang)] : []),
    ...actions.map(button),
    ...(hints ? [el('span', 'hints', hints)] : []),
  ];

  const api = {
    host,
    shadow,
    // text without trailing dots: the card animates them.
    working(text, { onCancel } = {}) {
      render([el('span', 'msg dots', text.replace(/(\.\.\.|…)$/, '')), ...(onCancel ? [button({ label: 'Cancel', onClick: onCancel })] : [])]);
    },
    preview({ text, model, lang, onLang, actions = [], hints = '' }) {
      render([el('span', 'msg', text), ...(model ? [el('span', 'model', modelLabel(model))] : []), ...trailing(lang, onLang, actions, hints)]);
    },
    message(text, { actions = [], error = false, lang, onLang } = {}) {
      render([el('span', 'msg', text), ...trailing(lang, onLang, actions, '')], { error });
    },
    hide() {
      host.remove();
      unbindTheme?.();
      unbindTheme = null;
      if (place.float) {
        win.removeEventListener('scroll', placeFloat, true);
        win.removeEventListener('resize', placeFloat);
      }
    },
    isOpen: () => host.isConnected,
  };
  return api;
}
