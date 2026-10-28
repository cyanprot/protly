// Classic content script for Gmail. Content scripts cannot be ES modules, so load the real entry dynamically.
(async () => {
  try {
    const { start } = await import(chrome.runtime.getURL('src/content/gmail/main.js'));
    await start();
  } catch (e) {
    console.error('[protly] Gmail part failed to load', e);
  }
})();
