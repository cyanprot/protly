// Global toggles set from the toolbar popup. Mutable on purpose: tests set flags.polish directly.
// Cached here because Enter has to be blocked synchronously, before a storage read could return.
export const flags = { polish: false };

export function watchFlags() {
  chrome.storage.local.get('polish').then((r) => { flags.polish = r.polish === true; }).catch(() => {});
  chrome.storage.onChanged.addListener((ch, area) => {
    if (area === 'local' && 'polish' in ch) flags.polish = ch.polish.newValue === true;
  });
}
