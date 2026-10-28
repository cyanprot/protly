import { watchFlags, siteEnabled } from '../../lib/flags.js';
import { addFonts, fetchFonts } from '../../ui/fonts.js';
import { GSEL } from './selectors.js';
import { mountCompose, translate, escape } from './compose.js';
import { commandListener } from '../../lib/command.js';

const SCAN_MS = 300;

export async function start() {
  if (!(await siteEnabled('gmail'))) return; // switched off in the popup: mount nothing
  fetchFonts((p) => chrome.runtime.getURL(p)).then((f) => addFonts(document, f))
    .catch((e) => console.warn('[protly] fonts not loaded; using the monospace fallback', e));
  watchFlags();
  let timer = null;
  const scan = () => { timer = null; document.querySelectorAll(GSEL.body).forEach(mountCompose); };
  // Throttle, not debounce: Gmail mutates the page often enough that a debounce could never fire.
  new MutationObserver(() => { timer ??= setTimeout(scan, SCAN_MS); })
    .observe(document.body, { childList: true, subtree: true });
  scan();

  // Esc in a compose body undoes protly's preview. Only swallowed when there was something to undo.
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || e.isComposing) return;
    const body = e.target?.closest?.(GSEL.body);
    if (!body || !escape(body)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
  }, true);

  // Alt+T arrives as a background command. The compose body owns it when focus is inside one.
  let composing = false;
  document.addEventListener('compositionstart', () => { composing = true; }, true);
  document.addEventListener('compositionend', () => { composing = false; }, true);
  chrome.runtime.onMessage.addListener(commandListener({
    owner: () => document.activeElement?.closest?.(GSEL.body) ?? null,
    composing: () => composing,
    run: (body) => { if (body.isConnected) translate(body); },
  }));
}
