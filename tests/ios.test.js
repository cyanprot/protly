import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const raw = readFileSync(new URL('../ios/body-template.json', import.meta.url), 'utf8');
const body = JSON.parse(raw);

test('iOS template is one ASCII line with each slot once, as a plain token', () => {
  assert.equal(raw.trimEnd().includes('\n'), false);
  assert.ok(/^[\x20-\x7e]*\n?$/.test(raw));
  assert.equal(raw.split('{{IMAGE_B64}}').length, 2);
  assert.equal(raw.split('{{TEXT}}').length, 2);
  const [image, text] = body.messages[0].content;
  assert.equal(image.source.data, '{{IMAGE_B64}}');
  assert.equal(image.source.media_type, 'image/jpeg');
  assert.equal(text.text, '{{TEXT}}');
});

test('iOS template system prompt matches ios/system-prompt.txt', () => {
  const src = readFileSync(new URL('../ios/system-prompt.txt', import.meta.url), 'utf8').trim();
  assert.equal(body.system, src);
});

test('iOS template asks for the translation schema', () => {
  assert.equal(body.model, 'claude-sonnet-5-5');
  assert.ok(body.max_tokens > 0);
  assert.deepEqual(body.thinking, { type: 'between_tools' }); // MODE in: thinking off, like the extension's incoming
  const f = body.output_config.format;
  assert.equal(f.type, 'json_schema');
  assert.deepEqual(f.schema.required, ['translation', 'back_translation']);
});

test('the Cherri source carries the same template, with no apostrophe', () => {
  const src = readFileSync(new URL('../ios/protly.cherri', import.meta.url), 'utf8');
  const m = src.match(/^@template = '(.*)'$/m);
  assert.ok(m);
  assert.equal(m[1], raw.trim());
  assert.equal(raw.includes("'"), false);
});

test('the Cherri source takes the key from a placeholder Text action and guards it', () => {
  const src = readFileSync(new URL('../ios/protly.cherri', import.meta.url), 'utf8');
  const code = src.split('\n').filter((l) => l.trim() && !/^\s*(\/\/|#include|action )/.test(l));
  assert.equal(code[0], '@keyText = "PASTE_API_KEY_HERE"');
  assert.equal(src.includes('#question'), false);
  assert.match(src, /matchText\('\^sk-ant-'/);
});

test('the Cherri source has the fix mode and expiring clipboard results', () => {
  const src = readFileSync(new URL('../ios/protly.cherri', import.meta.url), 'utf8');
  assert.match(src, /MODE: fix/);
  assert.match(src, /adjustDate\("\{now\}", "Add", qty\(3, "min"\)\)/);
  assert.match(src, /setClipboard\(translation, false, "\{expiry\}"\)/);
});

test('mode comes from the launch input, and the write shortcut passes it', () => {
  const src = readFileSync(new URL('../ios/protly.cherri', import.meta.url), 'utf8');
  const write = readFileSync(new URL('../ios/protly-write.cherri', import.meta.url), 'utf8');
  assert.match(src, /const writeFlag = matchText\('\^write\$', "\{ShortcutInput\}"\)/);
  // The clipboard is read only inside the write branch.
  assert.ok(src.indexOf('getClipboard()') > src.indexOf('if writeFlag {'));
  assert.match(write, /@flag = "write"\nrun\("Protly", @flag\)/);
});

test('drafts swap in Opus with adaptive thinking, reading the screen stays on Sonnet', () => {
  const src = readFileSync(new URL('../ios/protly.cherri', import.meta.url), 'utf8');
  const i = src.indexOf('if @mode != "in" {');
  assert.ok(i > src.indexOf("@template = '") && i < src.indexOf("replaceText('{{TEXT}}'"));
  assert.match(src, /replaceText\('claude-sonnet-5-5', "claude-opus-5-5"/);
  assert.match(src, /replaceText\('between_tools', "adaptive"/);
});

test('MODE in skips reply quotes and interface text', () => {
  const sys = readFileSync(new URL('../ios/system-prompt.txt', import.meta.url), 'utf8');
  assert.match(sys, /A quote is not a message/);
  assert.match(sys, /truncation markers/);
});
