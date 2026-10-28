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
  const f = body.output_config.format;
  assert.equal(f.type, 'json_schema');
  assert.deepEqual(f.schema.required, ['translation', 'back_translation']);
});

test('the Cherri source carries the same template, with no apostrophe', () => {
  const src = readFileSync(new URL('../ios/ig-translate.cherri', import.meta.url), 'utf8');
  const m = src.match(/^@template = '(.*)'$/m);
  assert.ok(m);
  assert.equal(m[1], raw.trim());
  assert.equal(raw.includes("'"), false);
});

test('the Cherri source takes the key from a placeholder Text action and guards it', () => {
  const src = readFileSync(new URL('../ios/ig-translate.cherri', import.meta.url), 'utf8');
  const code = src.split('\n').filter((l) => l.trim() && !/^\s*(\/\/|#include|action )/.test(l));
  assert.equal(code[0], '@keyText = "PASTE_API_KEY_HERE"');
  assert.equal(src.includes('#question'), false);
  assert.match(src, /matchText\('\^sk-ant-'/);
});
