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
  assert.ok(war.resources.includes('src/content/gmail/main.js')); // the exact list is checked in war.test.js
  assert.ok(war.resources.includes('src/lib/lang.js'));
});

test('the toolbar popup is wired and has the control-center fields', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.equal(m.action.default_popup, 'popup/popup.html');
  const html = readFileSync(new URL('../popup/popup.html', import.meta.url), 'utf8');
  for (const id of ['polish', 'site-instagram', 'site-gmail', 'status', 'today', 'month', 'options']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
  assert.match(html, /Polish English on Enter \(Instagram\)/);
  assert.match(html, /wordmark\.svg/);
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

test('both content-script origins can load the shared UI modules and fonts', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  for (const origin of ['https://www.instagram.com/*', 'https://mail.google.com/*']) {
    const war = m.web_accessible_resources.find((w) => w.matches.includes(origin));
    assert.ok(war.resources.includes('src/ui/card.js'), origin);
    assert.ok(war.resources.includes('src/ui/fonts/protly-mono-400.woff2'), origin);
  }
});

// No test drives these modules end to end; importing them catches broken imports and duplicate declarations.
test('content modules import cleanly', async () => {
  for (const p of ['../src/content/main.js', '../src/content/outgoing.js', '../src/content/panel.js',
    '../src/content/gmail/main.js', '../src/content/gmail/compose.js']) {
    await import(new URL(p, import.meta.url));
  }
});

test('options page saves on change and has diagnostics', () => {
  const html = readFileSync(new URL('../options/options.html', import.meta.url), 'utf8');
  assert.doesNotMatch(html, /id="save"/);
  for (const id of ['incoming', 'outgoing', 'hard', 'otherTarget', 'pastMode', 'newMode', 'saved', 'check', 'host-result', 'test', 'test-result', 'ext-id']) {
    assert.match(html, new RegExp(`id="${id}"`), id);
  }
});

test('the host error points to the diagnostics', async () => {
  const { ERRORS } = await import('../src/ui/errors.js');
  assert.equal(ERRORS.host, 'Native host not reachable. Open protly options and run Diagnostics.');
});

test('manifest has the any-site permissions and the Alt+T command', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  for (const p of ['scripting', 'contextMenus']) assert.ok(m.permissions.includes(p), p);
  assert.equal(m.permissions.filter((p) => p === 'activeTab').length, 1); // added in Task 3.5
  assert.equal(m.commands.run.suggested_key.default, 'Alt+T');
  assert.match(m.commands.run.description, /focused text box/);
  // dist/generic.js is injected by the background, never exposed to pages
  for (const w of m.web_accessible_resources) assert.equal(w.resources.some((r) => r.startsWith('dist/')), false);
  assert.equal((m.host_permissions || []).some((h) => h === '<all_urls>' || h.startsWith('*://')), false);
});
