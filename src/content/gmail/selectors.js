// Every Gmail DOM assumption lives here (docs/spike-notes-gmail.md). When Gmail changes, re-check and edit this file.
export const GSEL = {
  body: 'div[role="textbox"][aria-label="Message Body"][contenteditable="true"]',
  send: '[role="button"][data-tooltip^="Send"]',
  threadItem: '[role="listitem"]',
  messageBody: 'div.a3s', // Gmail class name, the only body anchor; expanded messages only
  sender: 'h3 span[email]',
  account: 'a[aria-label^="Google Account:"]',
  // Blocks in a compose body that are not the user's own text and must never be rewritten. A bare
  // <blockquote> is not one: Gmail's "Indent more" wraps the user's own paragraph in it.
  boundary: '.gmail_quote, .gmail_signature, .gmail_signature_prefix',
  // Stripped from received messages when reading the thread (other mail clients quote with <blockquote>).
  quoted: '.gmail_quote, blockquote, .gmail_signature, .gmail_signature_prefix',
};

// The compose container: the nearest ancestor of the body that holds a Send button, and only if it holds
// no other compose body. null while the toolbar has not rendered yet, so a button never lands next to
// another compose's Send.
export function composeOf(body) {
  for (let c = body.parentElement; c; c = c.parentElement) {
    if (c.querySelector(GSEL.send)) return c.querySelectorAll(GSEL.body).length === 1 ? c : null;
  }
  return null;
}

// Label shape: "Google Account: <name> (<email>)". null if not found.
export function findViewerEmail(doc) {
  const label = doc.querySelector(GSEL.account)?.getAttribute('aria-label') || '';
  const m = label.match(/\(([^()\s]+@[^()\s]+)\)\s*$/);
  return m ? m[1].toLowerCase() : null;
}
