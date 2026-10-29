// Size limits on what content scripts send the background (checked in messages.js). The adapters bound page text
// to these too, so one oversized message is skipped or cut instead of failing a whole request.
export const LIMITS = { text: 32000, memo: 8000, items: 1000, context: 50, texts: 1000, reason: 200, url: 2 * 1024 * 1024 }; // url: Chrome's own URL limit

// list in pieces of at most n, in order: lists longer than a limit go to the background in several messages.
export function chunks(list, n) {
  const out = [];
  for (let i = 0; i < list.length; i += n) out.push(list.slice(i, i + n));
  return out;
}
