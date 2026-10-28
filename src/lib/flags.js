// Global toggles set from the toolbar popup. Mutable on purpose: tests set flags.polish directly.
// Cached here because Enter has to be blocked synchronously, before a storage read could return.
export const DEFAULT_SITES = { instagram: true, gmail: true };
export const flags = { polish: false, sites: { ...DEFAULT_SITES } };

let ready = null;

function apply(values) {
  if ('polish' in values) flags.polish = values.polish === true;
  if ('sites' in values) flags.sites = { ...DEFAULT_SITES, ...(values.sites || {}) };
}

// Resolves once the stored values are in; later changes keep arriving through storage.onChanged.
export function watchFlags() {
  ready ??= (async () => {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      const picked = {};
      for (const k of ['polish', 'sites']) if (k in changes) picked[k] = changes[k].newValue;
      apply(picked);
    });
    try {
      apply(await chrome.storage.local.get(['polish', 'sites']));
    } catch {} // defaults stay; the next onChanged corrects them
  })();
  return ready;
}

// A site switched off mounts nothing on its next page load.
export async function siteEnabled(site) {
  await watchFlags();
  return flags.sites[site] !== false;
}

export function _resetFlags() {
  ready = null;
  flags.polish = false;
  flags.sites = { ...DEFAULT_SITES };
}
