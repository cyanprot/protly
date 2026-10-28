import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { flags, watchFlags, siteEnabled, DEFAULT_SITES, _resetFlags } from '../src/lib/flags.js';

// A chrome.storage stub holding `stored`; change() fires storage.onChanged like Chrome does.
function stubChrome(stored, { failGet = false } = {}) {
  const listeners = [];
  globalThis.chrome = {
    storage: {
      local: {
        get: async (keys) => {
          if (failGet) throw new Error('storage down');
          const out = {};
          for (const k of [].concat(keys)) if (k in stored) out[k] = stored[k];
          return out;
        },
      },
      onChanged: { addListener: (f) => listeners.push(f) },
    },
    runtime: {
      sendMessage: async () => ({ ok: true, data: true }), getURL: (p) => `chrome-extension://x/${p}`,
      onMessage: { addListener() {} }, // Sprint 4's Gmail start() registers the command listener
    },
  };
  return {
    listeners,
    change: (ch, area = 'local') => listeners.forEach((f) => f(ch, area)),
  };
}

beforeEach(() => _resetFlags());

test('defaults: polish off, every site on', async () => {
  stubChrome({});
  await watchFlags();
  assert.equal(flags.polish, false);
  assert.deepEqual(flags.sites, DEFAULT_SITES);
  assert.deepEqual(DEFAULT_SITES, { instagram: true, gmail: true });
});

test('stored values load before watchFlags resolves; a partial sites object keeps the other defaults', async () => {
  stubChrome({ polish: true, sites: { gmail: false } });
  await watchFlags();
  assert.equal(flags.polish, true);
  assert.deepEqual(flags.sites, { instagram: true, gmail: false });
});

test('storage changes flow in; other areas and keys are ignored', async () => {
  const c = stubChrome({});
  await watchFlags();
  c.change({ sites: { newValue: { instagram: false, gmail: true } }, polish: { newValue: true } });
  assert.deepEqual(flags.sites, { instagram: false, gmail: true });
  assert.equal(flags.polish, true);
  c.change({ polish: { newValue: false } }, 'session');
  assert.equal(flags.polish, true);
  c.change({ polish: {} }); // key removed: back to off
  assert.equal(flags.polish, false);
});

test('watchFlags is idempotent: one listener, same promise', async () => {
  const c = stubChrome({});
  const a = watchFlags();
  const b = watchFlags();
  assert.equal(a, b);
  await a;
  assert.equal(c.listeners.length, 1);
});

test('a failing storage read still resolves, with defaults', async () => {
  stubChrome({}, { failGet: true });
  await watchFlags();
  assert.deepEqual(flags.sites, DEFAULT_SITES);
});

test('siteEnabled reads the stored switch', async () => {
  stubChrome({ sites: { instagram: false } });
  assert.equal(await siteEnabled('instagram'), false);
  assert.equal(await siteEnabled('gmail'), true);
});

test('Gmail start mounts nothing when Gmail is off, and mounts the button when on', async () => {
  const html = readFileSync(new URL('./fixtures/gmail.html', import.meta.url), 'utf8');
  const { start } = await import('../src/content/gmail/main.js');

  const off = new JSDOM(`<body>${html}</body>`).window;
  globalThis.document = off.document;
  globalThis.MutationObserver = off.MutationObserver;
  stubChrome({ sites: { gmail: false } });
  await start();
  assert.equal(document.querySelectorAll('.pl-g-btn').length, 0);

  _resetFlags();
  const on = new JSDOM(`<body>${html}</body>`).window;
  globalThis.document = on.document;
  globalThis.MutationObserver = on.MutationObserver;
  stubChrome({});
  await start();
  assert.ok(document.querySelectorAll('.pl-g-btn').length > 0);
});

test('Instagram start returns before any timer or listener when Instagram is off', async () => {
  const { start } = await import('../src/content/main.js');
  stubChrome({ sites: { instagram: false } });
  const realSetInterval = globalThis.setInterval;
  let timers = 0;
  globalThis.setInterval = () => { timers++; return 0; };
  try {
    await start();
  } finally {
    globalThis.setInterval = realSetInterval;
  }
  assert.equal(timers, 0);
});
