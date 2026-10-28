// Reads and writes a text box on any site. textarea/input: setRangeText plus an input event, which React-style
// controlled inputs notice (their value tracker sees the change). contenteditable: select all and
// execCommand('insertText'), the path the Instagram writer uses, so the editor's own undo and state stay in sync.
export const SELECT_SETTLE_MS = 60; // editors such as Lexical sync their selection on selectionchange

const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();

export function readBox(t) {
  if (t.kind === 'text') return t.el.value;
  return (t.el.innerText ?? t.el.textContent ?? '').replace(/\n$/, '');
}

function setValue(el, text) {
  try {
    el.setRangeText(text, 0, el.value.length, 'end');
  } catch {
    // email inputs have no selection API: use the native setter so frameworks still see a change
    const proto = Object.getPrototypeOf(el);
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
  }
  const win = el.ownerDocument.defaultView;
  const Ev = win?.InputEvent || win?.Event;
  el.dispatchEvent(new Ev('input', { bubbles: true, inputType: 'insertReplacementText', data: text }));
}

// true only when the box ends up holding text (whitespace-normalized). The caller restores on false.
export async function writeBox(t, text, { settleMs = SELECT_SETTLE_MS } = {}) {
  const { el } = t;
  if (!el.isConnected) return false;
  el.focus();
  if (t.kind === 'text') {
    setValue(el, text);
  } else {
    el.ownerDocument.getSelection().selectAllChildren(el);
    await new Promise((r) => setTimeout(r, settleMs));
    if (!el.isConnected) return false;
    el.focus();
    el.ownerDocument.execCommand('insertText', false, text);
  }
  return norm(readBox(t)) === norm(text);
}
