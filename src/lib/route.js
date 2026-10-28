// Adapter-first routing for Alt+T and the context menu. All Chrome calls are injected so this stays testable.
// Returns 'adapter' | 'generic' | 'unavailable'.
export async function routeCommand({ tabId, frameId = 0, args, sendToTab, injectFile, runGeneric, setBadge, toastInMain }) {
  // A selection always goes to the generic popover: an adapter would take the whole draft around it.
  if (args?.source !== 'menu-selection') {
    let answer = null;
    try { answer = await sendToTab(tabId, { type: 'command' }, frameId); } catch {} // no content script there
    if (answer?.handled) return 'adapter';
  }

  try {
    await injectFile(tabId, frameId);
  } catch {
    // chrome:// pages and the Web Store refuse the main frame: badge. A refused cross-origin frame on an ordinary
    // page gets a toast from the main frame instead; the badge would mark the whole tab unavailable.
    if (frameId !== 0) {
      try {
        await injectFile(tabId, 0);
        await toastInMain(tabId, 'protly cannot reach this frame.');
        return 'unavailable';
      } catch {}
    }
    await setBadge(tabId, '!', 'unavailable here');
    return 'unavailable';
  }
  try {
    await runGeneric(tabId, frameId, args);
  } catch (e) {
    console.warn('[protly] generic run failed', e); // the bundle reports its own errors in the page
  }
  return 'generic';
}
