// Korean IME helpers. A shortcut or a message carries no composition state, and the last syllable of a Korean
// composition is not in the box until the composition ends.

// One animation frame (a timer when there is none, as in node tests).
export const nextFrame = () => new Promise((r) => {
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(() => r());
  else setTimeout(r, 16);
});

// Blurring ends any open composition (the browser commits it); refocus and put the caret back.
export function commitByRefocus(el) {
  const doc = el.ownerDocument;
  let restore = () => {};
  if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
    let start = null;
    let end = null;
    try { start = el.selectionStart; end = el.selectionEnd; } catch {} // email inputs have no selection API
    restore = () => { if (start != null) { try { el.setSelectionRange(start, end); } catch {} } };
  } else {
    const sel = doc.getSelection();
    const range = sel && sel.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
    restore = () => {
      if (!range) return;
      const s = doc.getSelection();
      s.removeAllRanges();
      s.addRange(range);
    };
  }
  el.blur();
  el.focus();
  restore();
}

// Waits until no composition is open in el: at once when composing is false, else until compositionend or the
// timeout (then commitByRefocus), plus one frame so the committed text lands.
export async function settleComposition(el, { composing = false, timeoutMs = 500 } = {}) {
  if (composing) {
    await new Promise((resolve) => {
      let timer = null;
      const done = (timedOut) => {
        clearTimeout(timer);
        el.removeEventListener('compositionend', onEnd);
        if (timedOut) commitByRefocus(el);
        resolve();
      };
      const onEnd = () => done(false);
      timer = setTimeout(() => done(true), timeoutMs);
      el.addEventListener('compositionend', onEnd);
    });
  }
  await nextFrame();
}
