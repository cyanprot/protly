import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { statusFor, GENERIC_TEXT } from '../src/lib/status.js';

const ON = { instagram: true, gmail: true };

test('restricted or unknown pages are unavailable', () => {
  for (const url of [
    undefined, '', 'chrome://extensions/', 'chrome-extension://abc/popup/popup.html', 'edge://settings',
    'about:blank', 'view-source:https://example.com/', 'devtools://devtools/x', 'file:///home/cyan/a.html',
    'https://chrome.google.com/webstore/detail/x', 'https://chromewebstore.google.com/detail/x',
  ]) {
    assert.deepEqual(statusFor({ url, sites: ON }), { state: 'unavailable', text: 'Unavailable here' }, String(url));
  }
});

test('Instagram and Gmail: active when on, site-off when off', () => {
  assert.deepEqual(statusFor({ url: 'https://www.instagram.com/direct/t/1/', sites: ON }),
    { state: 'instagram', text: 'Instagram: active' });
  assert.deepEqual(statusFor({ url: 'https://mail.google.com/mail/u/0/#inbox', sites: ON }),
    { state: 'gmail', text: 'Gmail: active' });
  assert.deepEqual(statusFor({ url: 'https://www.instagram.com/', sites: { ...ON, instagram: false } }),
    { state: 'site-off', text: 'Instagram: off' });
  assert.deepEqual(statusFor({ url: 'https://mail.google.com/', sites: { ...ON, gmail: false } }),
    { state: 'site-off', text: 'Gmail: off' });
});

test('a badge with a reason is a problem', () => {
  assert.deepEqual(
    statusFor({ url: 'https://mail.google.com/', sites: ON, badge: { text: '!', reason: 'Gmail Send button not found' } }),
    { state: 'problem', text: 'Problem: Gmail Send button not found' },
  );
  assert.deepEqual(statusFor({ url: 'https://example.com/', sites: ON, badge: { text: '!', reason: '' } }),
    { state: 'problem', text: 'Problem on this page' });
});

test('any other web page is generic; missing sites means defaults', () => {
  assert.deepEqual(statusFor({ url: 'https://example.com/form' }), { state: 'generic', text: GENERIC_TEXT });
  assert.equal(GENERIC_TEXT, 'Alt+T ready');
});

test('manifest grants activeTab so the popup can read the current tab', () => {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url)));
  assert.ok(m.permissions.includes('activeTab'));
});

test('a refused injection reads as unavailable, not as a problem', () => {
  assert.deepEqual(
    statusFor({ url: 'https://example.com/', sites: ON, badge: { text: '!', reason: 'unavailable here' } }),
    { state: 'unavailable', text: 'Unavailable here' },
  );
});
