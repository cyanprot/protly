// Size limits on what content scripts send the background (checked in messages.js). The adapters bound page text
// to these too, so one oversized message is skipped or cut instead of failing a whole request.
export const LIMITS = { text: 32000, memo: 8000, items: 1000, context: 50, texts: 1000, reason: 200, url: 8192 };
