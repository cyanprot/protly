import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { extensionId } from '../scripts/extension-id.mjs';

// Vector computed 2026-10-28: sha256 of these DER bytes starts a1e9156054e04fac899ae9f275132cdc.
test('extensionId maps the first 16 bytes of sha256(DER) to a-p', () => {
  assert.equal(extensionId('MCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE='), 'kbojbfgafeoaepkmijjkojpchfbdcmnm');
});

test('manifest.json carries a key that yields a 32-letter a-p ID', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url), 'utf8'));
  assert.equal(typeof m.key, 'string');
  assert.match(extensionId(m.key), /^[a-p]{32}$/);
});
