// ordered: bubbles in DOM order (top to bottom). isKnown: already-seen check.
// Unknown bubbles after the last known one are fresh arrivals; all others are back-filled history.
export function classifyAdded(ordered, isKnown) {
  let lastKnown = -1;
  ordered.forEach((x, i) => { if (isKnown(x)) lastKnown = i; });
  const past = [];
  const fresh = [];
  ordered.forEach((x, i) => { if (!isKnown(x)) (i > lastKnown ? fresh : past).push(x); });
  return { past, fresh };
}
