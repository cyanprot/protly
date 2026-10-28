// Why a tab shows the "!" badge, for the popup. Kept in chrome.storage.session: gone when the browser closes.
const key = (tabId) => `badge:${tabId}`;

export function createBadgeStore(session) {
  return {
    async set(tabId, { text, reason = '' }) {
      if (tabId == null) return;
      if (!text) { await session.remove(key(tabId)); return; }
      await session.set({ [key(tabId)]: { text, reason } });
    },
    clear: (tabId) => session.remove(key(tabId)),
    async get(tabId) {
      const k = key(tabId);
      return (await session.get(k))[k] || null;
    },
  };
}
