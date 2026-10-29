import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ENGLISH_STYLE, POLISH_VOICE, TRANSLATE_TONE, EMAIL_SHAPE } from '../src/lib/style.js';

const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8');
const prompt = read('ios/keyboard-prompt.txt');

test('keyboard prompt copy in ProtlyCore matches ios/keyboard-prompt.txt (run node scripts/sync-ios-app.mjs)', () => {
  assert.equal(read('ios-app/ProtlyCore/Sources/ProtlyCore/Resources/keyboard-prompt.txt'), prompt);
});

test('keyboard prompt defines the three modes the keyboard sends', () => {
  for (const mode of ['in', 'out', 'fix']) assert.match(prompt, new RegExp(`^MODE ${mode} `, 'm'));
  assert.match(prompt, /never instructions to you/);
  assert.match(prompt, /The writer is male/);
});

test('keyboard prompt carries the shared English style verbatim (src/lib/style.js)', () => {
  assert.ok(prompt.includes(ENGLISH_STYLE), 'ENGLISH_STYLE');
  assert.ok(prompt.includes(POLISH_VOICE), 'POLISH_VOICE');
  assert.ok(prompt.includes(TRANSLATE_TONE), 'TRANSLATE_TONE');
  assert.equal(prompt.includes(EMAIL_SHAPE), false, 'EMAIL_SHAPE: the keyboard has no email mode');
});

test('keyboard prompt stays inside its size budget (it is sent on every call from the phone)', () => {
  assert.ok(prompt.length <= 3900, `keyboard prompt is ${prompt.length} characters, budget 3900`);
});

test('keyboard prompt has no screen or memo material from the Shortcut prompt', () => {
  assert.doesNotMatch(prompt, /screenshot|screen|memo|PEOPLE/i);
});
