import { watchFlags } from '../../lib/flags.js';
import { GSEL } from './selectors.js';
import { mountCompose, translate, escape } from './compose.js';

const SCAN_MS = 300;
const COMPOSE_WAIT_MS = 500;

export async function start() {
  watchFlags();
  let timer = null;
  const scan = () => { timer = null; document.querySelectorAll(GSEL.body).forEach(mountCompose); };
  // Throttle, not debounce: Gmail mutates the page often enough that a debounce could never fire.
  new MutationObserver(() => { timer ??= setTimeout(scan, SCAN_MS); })
    .observe(document.body, { childList: true, subtree: true });
  scan();

  // Alt+T inside a compose body. e.code, because the Korean layout reports e.key as 'ㅅ'.
  document.addEventListener('keydown', (e) => {
    if (!e.altKey || e.ctrlKey || e.metaKey || e.shiftKey || e.code !== 'KeyT') return;
    const body = e.target?.closest?.(GSEL.body);
    if (!body) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (!e.isComposing && e.keyCode !== 229) { translate(body); return; }
    // IME mid-syllable: wait for the last syllable to commit.
    const go = () => { clearTimeout(t); translate(body); };
    const t = setTimeout(() => { body.removeEventListener('compositionend', go); translate(body); }, COMPOSE_WAIT_MS);
    body.addEventListener('compositionend', go, { once: true });
  }, true);

  // Esc in a compose body undoes protly's preview. Only swallowed when there was something to undo.
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || e.isComposing) return;
    const body = e.target?.closest?.(GSEL.body);
    if (!body || !escape(body)) return;
    e.preventDefault();
    e.stopImmediatePropagation();
  }, true);
}
