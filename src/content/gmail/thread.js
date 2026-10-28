import { GSEL } from './selectors.js';
import { nodesToText } from './body.js';

// Context for a reply: expanded messages of the open thread, oldest first. Collapsed messages have no body
// in the DOM and are skipped; the last message of a thread is always expanded.
export function readThread(root, viewerEmail, { maxMessages = 5, maxChars = 1500 } = {}) {
  const out = [];
  for (const item of root.querySelectorAll(GSEL.threadItem)) {
    const body = item.querySelector(GSEL.messageBody);
    if (!body) continue;
    const clone = body.cloneNode(true);
    clone.querySelectorAll(GSEL.boundary).forEach((n) => n.remove()); // quoted history, signatures
    let text = nodesToText([...clone.childNodes]).replace(/\n{3,}/g, '\n\n').trim();
    if (!text) continue;
    if (text.length > maxChars) text = `${text.slice(0, maxChars)} [...]`;
    const email = item.querySelector(GSEL.sender)?.getAttribute('email')?.toLowerCase();
    out.push({ from: viewerEmail && email === viewerEmail ? 'me' : 'them', text });
  }
  return out.slice(-maxMessages);
}
