import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('manifest is valid JSON with MV3', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(m.manifest_version, 3);
  assert.equal(m.background.type, 'module');
});
