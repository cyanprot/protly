// User-facing text per ApiError kind (src/lib/api.js), shared by Instagram, Gmail and the generic path.
export const ERRORS = {
  auth: 'API key missing or rejected. Check ~/.config/anthropic/api-key.',
  host: 'Native host not reachable. Open protly options and run Diagnostics.',
  host_bug: 'The native host hit an error',
  spend_limit: 'Monthly API spend limit reached. Paused until the limit resets.',
  bad_request: 'The API rejected the request (check the model ids in Options)',
  stale: 'protly was reloaded or updated. Reload this tab.',
  timeout: 'The model took too long. Try again.',
  network: 'Network error. Check the connection and try again.',
  rate: 'Rate limited. Try again in a moment.',
  overloaded: 'The API is overloaded. Try again in a moment.',
  server: 'The API had a server error. Try again.',
  refused: 'The model declined this text.',
  truncated: 'The reply was cut off. Try Opus or a shorter text.',
  parse: 'The reply was not readable. Try again.',
};
// Kinds worth a page toast (once per text), not only an inline message. Replaces bannerFor's list.
export const GLOBAL_KINDS = new Set(['auth', 'host', 'host_bug', 'spend_limit', 'bad_request', 'stale']);
export function errorText(e) {
  const base = ERRORS[e?.kind];
  if (!base) return String(e?.message || e || 'Unknown error');
  return e.kind === 'host_bug' || e.kind === 'bad_request' ? `${base}: ${e.message}` : base;
}
