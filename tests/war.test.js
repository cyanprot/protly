// web_accessible_resources: each site may load exactly the modules its content script imports (the loader's
// chrome.runtime.getURL import and everything reachable from it), plus the two fonts. Nothing else.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { posix } from 'node:path';

const root = new URL('../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');
const m = JSON.parse(read('manifest.json'));

function graph(entry) {
  const seen = new Set();
  const walk = (p) => {
    if (seen.has(p)) return;
    seen.add(p);
    const src = read(p);
    const specs = [...src.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*)['"](\.{1,2}\/[^'"]+)['"]/g)].map((x) => x[1]);
    for (const s of specs) walk(posix.normalize(posix.join(posix.dirname(p), s)));
  };
  walk(entry);
  return seen;
}

const FONTS = ['src/ui/fonts/protly-mono-400.woff2', 'src/ui/fonts/protly-mono-500.woff2'];

for (const cs of m.content_scripts) {
  test(`${cs.matches[0]} exposes exactly what its content script loads`, () => {
    const loader = read(cs.js[0]);
    const entry = loader.match(/getURL\('([^']+)'\)/)[1];
    const need = new Set([...graph(entry), ...FONTS]);
    const war = m.web_accessible_resources.filter((w) => w.matches.some((x) => cs.matches.includes(x)));
    assert.equal(war.length, 1);
    assert.deepEqual(war[0].matches, cs.matches);
    assert.deepEqual([...war[0].resources].sort(), [...need].sort());
    assert.equal(war[0].resources.some((r) => r.includes('*')), false);
    for (const secret of ['src/lib/native.js', 'src/lib/api.js', 'src/lib/prompts.js', 'src/lib/messages.js', 'src/background.js']) {
      assert.equal(war[0].resources.includes(secret), false, secret);
    }
  });
}
