import { DEFAULT_SITES } from './flags.js';

// Pages no extension may touch (and file:/data: pages, which protly does not ask for).
const RESTRICTED = [
  /^chrome:/, /^chrome-extension:/, /^edge:/, /^about:/, /^view-source:/, /^devtools:/,
  /^https:\/\/chrome\.google\.com\/webstore/, /^https:\/\/chromewebstore\.google\.com/,
];
const UNAVAILABLE = { state: 'unavailable', text: 'Unavailable here' };
export const GENERIC_TEXT = 'Alt+T ready';

const SITES = { 'www.instagram.com': ['instagram', 'Instagram'], 'mail.google.com': ['gmail', 'Gmail'] };

// The popup's one-line status for the active tab. badge: { text, reason } from the badge store, or null.
export function statusFor({ url, sites = DEFAULT_SITES, badge = null }) {
  if (!url || RESTRICTED.some((r) => r.test(url)) || !/^https?:/.test(url)) return UNAVAILABLE;
  if (badge?.reason === 'unavailable here') return UNAVAILABLE; // routeCommand could not inject (Sprint 4)
  if (badge?.text) return { state: 'problem', text: badge.reason ? `Problem: ${badge.reason}` : 'Problem on this page' };
  let host;
  try { host = new URL(url).hostname; } catch { return UNAVAILABLE; }
  const site = SITES[host];
  if (site) {
    const [key, name] = site;
    return sites[key] !== false ? { state: key, text: `${name}: active` } : { state: 'site-off', text: `${name}: off` };
  }
  return { state: 'generic', text: GENERIC_TEXT };
}
