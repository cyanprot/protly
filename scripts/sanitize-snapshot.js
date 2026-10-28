// Run in the Instagram thread page (DevTools or Claude in Chrome javascript_tool).
// Returns sanitized HTML of the message list wrapped in <div role="main">, for tests/fixtures/thread.html.
// Set VIEWER to the logged-in username; it maps to viewer_user, every other name to partner_user.
(() => {
  const VIEWER = 'cyanprot';
  const arts = [...document.querySelectorAll('[role="main"] [role="article"][aria-roledescription="message"]')];
  let sc = arts[0];
  while (sc && !(/(auto|scroll)/.test(getComputedStyle(sc).overflowY) && sc.scrollHeight > sc.clientHeight + 50)) sc = sc.parentElement;
  const root = sc.cloneNode(true);
  let n = 0;
  const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const texts = [];
  while (w.nextNode()) texts.push(w.currentNode);
  for (const t of texts) if (t.nodeValue.trim()) t.nodeValue = `msg ${++n}`;
  root.querySelectorAll('svg').forEach((s) => s.replaceChildren());
  const KEEP = /^(role|aria-label|aria-roledescription|dir|data-igd-message-actions-hidden)$/;
  const LABELS = /^(Reply to message from|React to message from|See more options for message from|Open the profile page of|Message actions)/;
  for (const el of [root, ...root.querySelectorAll('*')]) {
    for (const at of [...el.attributes]) {
      if (!KEEP.test(at.name)) { el.removeAttribute(at.name); continue; }
      if (at.name === 'aria-label') {
        const v = at.value.replace(/(from |page of )(\S+)/g, (m, p, name) => p + (name === VIEWER ? 'viewer_user' : 'partner_user'));
        el.setAttribute('aria-label', LABELS.test(v) ? v : 'x');
      }
    }
  }
  return `<div role="main">${root.outerHTML.replace(/(<div><div><\/div><\/div>)+/g, '<div><div></div></div>')}</div>`;
})();
