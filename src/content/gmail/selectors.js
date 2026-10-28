// Every Gmail DOM assumption lives here (docs/spike-notes-gmail.md). When Gmail changes, re-check and edit this file.
export const GSEL = {
  body: 'div[role="textbox"][aria-label="Message Body"][contenteditable="true"]',
  send: '[role="button"][data-tooltip^="Send"]',
  threadItem: '[role="listitem"]',
  messageBody: 'div.a3s', // Gmail class name, the only body anchor; expanded messages only
  sender: 'h3 span[email]',
  account: 'a[aria-label^="Google Account:"]',
  // Blocks in a body that are not the user's own text and must never be rewritten.
  boundary: '.gmail_quote, blockquote, .gmail_signature, .gmail_signature_prefix',
};

// The compose container: nearest ancestor of the body that holds the Send button.
export function composeOf(body) {
  let c = body.parentElement;
  while (c && !c.querySelector(GSEL.send)) c = c.parentElement;
  return c;
}

// Label shape: "Google Account: <name> (<email>)". null if not found.
export function findViewerEmail(doc) {
  const label = doc.querySelector(GSEL.account)?.getAttribute('aria-label') || '';
  const m = label.match(/\(([^()\s]+@[^()\s]+)\)\s*$/);
  return m ? m[1].toLowerCase() : null;
}
