// Classic content script. Content scripts cannot be ES modules, so load the real entry dynamically.
(async () => {
  try {
    const { start } = await import(chrome.runtime.getURL('src/content/main.js'));
    await start();
  } catch (e) {
    console.error('[protly] failed to load', e);
  }
})();
