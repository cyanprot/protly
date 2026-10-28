import { TOKENS, BASE } from './tokens.css.js';
import { TOAST_CSS } from './toast.css.js';
import { bindTheme } from './theme.js';

const TRANSIENT_MS = 4000;
const shown = new Set(); // persistent toast texts already shown on this page
const lists = new WeakMap(); // document -> toast list element

export function _resetToasts() { shown.clear(); }

function listFor(doc) {
  let list = lists.get(doc);
  if (list?.isConnected) return list;
  const host = doc.createElement('div');
  host.className = 'pl-toasts';
  const root = host.attachShadow({ mode: 'open' });
  const style = doc.createElement('style');
  style.textContent = TOKENS + BASE + TOAST_CSS;
  list = doc.createElement('div');
  list.className = 'pl-root list';
  root.append(style, list);
  bindTheme(list, doc);
  (doc.body || doc.documentElement).appendChild(host);
  lists.set(doc, list);
  return list;
}

// transient: auto-dismiss and allow repeats (per-keypress feedback). Otherwise once per text per page.
export function showToast(text, { transient = false, error = false, doc = document } = {}) {
  if (shown.has(text)) return null;
  if (!transient) shown.add(text);
  const t = doc.createElement('div');
  t.className = error ? 'toast err' : 'toast';
  t.title = 'Click to dismiss';
  const label = doc.createElement('span');
  label.className = 'label';
  label.textContent = 'protly';
  const msg = doc.createElement('span');
  msg.className = 'msg';
  msg.textContent = text;
  t.append(label, msg);
  t.addEventListener('click', () => t.remove());
  listFor(doc).appendChild(t);
  if (transient) setTimeout(() => t.remove(), TRANSIENT_MS);
  return t;
}
