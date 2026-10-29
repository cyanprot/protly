// options/options.js loaded into options.html under jsdom, with a fake chrome. Diagnostics only: the host reply is
// faked, so no host runs and no key file is touched.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const html = readFileSync(new URL('../options/options.html', import.meta.url), 'utf8')
  .replace(/<script[^>]*><\/script>/g, ''); // the module is imported below, not run by jsdom
const flush = () => new Promise((r) => setTimeout(r, 0));
const HINT = 'chmod 600 ~/.config/anthropic/api-key';

// Loads a fresh page whose Check host answers with `diag`. Returns the result span and a click helper.
async function page(diag) {
  const { window } = new JSDOM(html);
  window.matchMedia = () => ({ matches: false, addEventListener() {} }); // jsdom has neither of these two
  window.document.adoptedStyleSheets = [];
  globalThis.document = window.document;
  globalThis.Option = window.Option;
  globalThis.chrome = {
    runtime: {
      id: 'abcdefghijklmnopabcdefghijklmnop',
      getURL: (p) => `chrome-extension://abcdefghijklmnopabcdefghijklmnop/${p}`,
      sendMessage: async (msg) => (msg.type === 'diag' ? { ok: true, data: diag } : { ok: false }),
    },
    storage: { local: { get: async () => ({}), set: async () => {} } },
  };
  // A fresh module instance per page: options.js wires the page at import.
  await import(`../options/options.js?${Math.random()}`);
  const result = document.getElementById('host-result');
  const check = async () => { document.getElementById('check').click(); await flush(); };
  return { result, check };
}

test('options Diagnostics: a shared key file shows the chmod 600 hint as an error', async () => {
  const { result, check } = await page({ ok: true, key_present: true, key_shared: true, workspace_header: true });
  await check();
  assert.ok(result.textContent.includes(HINT), result.textContent);
  assert.match(result.textContent, /key file open to group or others/);
  assert.ok(result.classList.contains('err'));
});

test('options Diagnostics: a private key file, or an older host with no key_shared, shows no hint', async () => {
  for (const extra of [{ key_shared: false }, {}]) {
    const { result, check } = await page({ ok: true, key_present: true, workspace_header: true, ...extra });
    await check();
    assert.match(result.textContent, /^Host OK · API key found · workspace header on$/, JSON.stringify(extra));
    assert.ok(!result.textContent.includes('chmod'), JSON.stringify(extra));
    assert.equal(result.classList.contains('err'), false, JSON.stringify(extra));
  }
});
