import { settleComposition } from './ime.js';

// Adapter side of Alt+T routing. owner() returns the adapter's focused box or null. When it owns the box the
// listener answers { handled: true } at once, then waits for any open IME composition and calls run(box).
// Otherwise it sends no answer, and the background injects the generic path.
export function commandListener({ owner, composing, run, settle = settleComposition }) {
  return (msg, _sender, sendResponse) => {
    if (msg?.type !== 'command') return false;
    let el = null;
    try { el = owner(); } catch {}
    if (!el) return false;
    sendResponse({ handled: true });
    settle(el, { composing: composing() })
      .then(() => run(el))
      .catch((e) => console.warn('[protly] command failed', e));
    return false;
  };
}
