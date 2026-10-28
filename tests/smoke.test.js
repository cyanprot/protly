import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('manifest is valid JSON with MV3', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(m.manifest_version, 3);
  assert.equal(m.background.type, 'module');
});

test('manifest uses native messaging, not direct API access', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.ok(m.permissions.includes('nativeMessaging'));
  assert.equal(m.host_permissions.some((h) => h.includes('anthropic')), false);
});

test('manifest injects the Gmail loader on mail.google.com', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  const g = m.content_scripts.find((c) => c.matches.includes('https://mail.google.com/*'));
  assert.deepEqual(g.js, ['src/content/gmail/loader.js']);
  assert.deepEqual(g.css, ['src/content/gmail/style.css']);
  const war = m.web_accessible_resources.find((w) => w.matches.includes('https://mail.google.com/*'));
  assert.ok(war.resources.includes('src/content/gmail/*.js'));
  assert.ok(war.resources.includes('src/lib/*.js'));
});

test('the toolbar popup is wired and present', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(m.action.default_popup, 'popup/popup.html');
  assert.match(readFileSync(new URL('../popup/popup.html', import.meta.url), 'utf8'), /id="polish"/);
});

test('the product is named protly everywhere a user or Chrome sees a name', async () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url), 'utf8'));
  assert.equal(m.name, 'protly');
  assert.equal(m.action.default_title, 'protly');
  const { HOST_NAME } = await import('../src/lib/native.js');
  assert.equal(HOST_NAME, 'com.northprot.protly');
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(pkg.name, 'protly');
});

test('protly-mono woff2 subsets exist and are small', () => {
  for (const w of ['400', '500']) {
    const buf = readFileSync(new URL(`../src/ui/fonts/protly-mono-${w}.woff2`, import.meta.url));
    assert.equal(buf.subarray(0, 4).toString('latin1'), 'wOF2');
    assert.ok(buf.length > 4000 && buf.length < 60000, `size ${buf.length}`);
  }
});

test('manifest icons point at the built p icon PNGs', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  const sizes = ['16', '32', '48', '128'];
  assert.deepEqual(Object.keys(m.icons), sizes);
  assert.deepEqual(m.action.default_icon, { 16: 'icons/icon-16.png', 32: 'icons/icon-32.png' });
  for (const s of sizes) {
    assert.equal(m.icons[s], `icons/icon-${s}.png`);
    const png = readFileSync(new URL(`../${m.icons[s]}`, import.meta.url));
    assert.equal(png.subarray(1, 4).toString('latin1'), 'PNG');
    assert.equal(png.readUInt32BE(16), Number(s)); // IHDR width
  }
  assert.match(readFileSync(new URL('../icons/wordmark.svg', import.meta.url), 'utf8'), /fill="currentColor"/);
});
