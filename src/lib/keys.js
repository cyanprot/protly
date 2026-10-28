export const PRUNE_MS = 90 * 24 * 60 * 60 * 1000;

export const DEFAULT_SETTINGS = {
  models: {
    incoming: 'claude-sonnet-5-5',
    outgoing: 'claude-opus-5-5',
    hard: 'claude-opus-5-5',
  },
  threadDefaults: { otherTarget: 'ko', pastMode: 'replace', newMode: 'below' },
};

const THREAD_BASE = { memo: '', partnerLang: null, outputLang: 'auto', enabled: true };

export function withThreadDefaults(stored, threadDefaults) {
  return { ...THREAD_BASE, ...DEFAULT_SETTINGS.threadDefaults, ...threadDefaults, ...stored };
}

export function threadIdFromPath(pathname) {
  const m = pathname.match(/^\/direct\/t\/([^/]+)/);
  return m ? m[1] : null;
}

export const threadKey = (id) => `t:${id}`;

async function sha256hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function cacheKey(threadId, text, otherTarget) {
  return 'c:' + (await sha256hex(JSON.stringify([threadId, text, otherTarget])));
}

// Whitespace-normalized: composer text at send time and bubble text read later must hash the same.
export async function sentKey(threadId, text) {
  return 's:' + (await sha256hex(JSON.stringify([threadId, text.replace(/\s+/g, ' ').trim()])));
}

export function expiredKeys(all, now) {
  return Object.entries(all)
    .filter(([k, v]) => (k.startsWith('c:') || k.startsWith('s:')) && typeof v?.ts === 'number' && now - v.ts > PRUNE_MS)
    .map(([k]) => k);
}
