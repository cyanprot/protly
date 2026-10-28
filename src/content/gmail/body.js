import { GSEL } from './selectors.js';

const BLOCK = /^(DIV|P|LI|H[1-6]|UL|OL|BLOCKQUOTE)$/;
const MEDIA = 'img, video, iframe';

const isBoundary = (n) => n.nodeType === 1 && (n.matches(GSEL.boundary) || !!n.querySelector(GSEL.boundary));
const isBlank = (n) =>
  n.nodeName === 'BR' ||
  (n.nodeType === 3 && !n.textContent.trim()) ||
  (n.nodeType === 1 && !n.textContent.trim() && !n.querySelector(MEDIA));

// The user's own part: body children before the first quote/signature block, minus trailing blank lines
// (those separate the draft from the signature and stay untouched).
export function userNodes(body) {
  const kids = [...body.childNodes];
  let end = kids.findIndex(isBoundary);
  if (end === -1) end = kids.length;
  while (end > 0 && isBlank(kids[end - 1])) end--;
  return kids.slice(0, end);
}

export const hasMedia = (nodes) => nodes.some((n) => n.nodeType === 1 && (n.matches(MEDIA) || !!n.querySelector(MEDIA)));

// Plain text with one \n per line, matching how Gmail lays out typed text (bare first line, <div> per line).
// Inline formatting is dropped.
export function nodesToText(nodes) {
  let out = '';
  const walk = (n) => {
    if (n.nodeType === 3) { out += n.textContent; return; }
    if (n.nodeType !== 1) return;
    if (n.nodeName === 'BR') { out += '\n'; return; }
    const block = BLOCK.test(n.nodeName);
    if (block && out && !out.endsWith('\n')) out += '\n';
    n.childNodes.forEach(walk);
    if (block && !out.endsWith('\n')) out += '\n';
  };
  nodes.forEach(walk);
  return out.replace(/\n$/, '');
}

// Gmail's own markup: <div>line</div>, blank line <div><br></div>. Built without innerHTML (Trusted Types).
export function textToNodes(doc, text) {
  return text.replace(/\r\n?/g, '\n').split('\n').map((line) => {
    const d = doc.createElement('div');
    if (line) d.textContent = line;
    else d.appendChild(doc.createElement('br'));
    return d;
  });
}

// Swap the user's part for newNodes; returns the removed nodes (for Undo). Quote and signature stay put.
// execCommand is not used: next to a block it clones the block's class onto the new lines (spike).
export function replaceUserNodes(body, newNodes) {
  const old = userNodes(body);
  const next = old.length ? old[old.length - 1].nextSibling : body.firstChild;
  old.forEach((n) => n.remove());
  const frag = body.ownerDocument.createDocumentFragment();
  newNodes.forEach((n) => frag.appendChild(n));
  body.insertBefore(frag, next);
  body.dispatchEvent(new body.ownerDocument.defaultView.Event('input', { bubbles: true }));
  return old;
}
