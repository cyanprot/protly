// Classic content script. Content scripts cannot be ES modules, so load the real entry dynamically.
(async () => {
  try {
    const { start } = await import(chrome.runtime.getURL('src/content/main.js'));
    await start();
  } catch (e) {
    console.error('[igt] failed to load', e);
  }
})();
