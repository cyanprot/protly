import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ENGLISH_STYLE, POLISH_VOICE, TRANSLATE_TONE, EMAIL_SHAPE } from '../src/lib/style.js';
import { LANG_NAMES } from '../src/lib/lang.js';

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
  assert.ok(prompt.length <= 4300, `keyboard prompt is ${prompt.length} characters, budget 4300`);
});

test('the keyboard translates into the extension languages (ProtlyCore Languages.swift equals LANG_NAMES)', () => {
  const swift = read('ios-app/ProtlyCore/Sources/ProtlyCore/Languages.swift');
  const pairs = [...swift.matchAll(/\("([a-z]{2,3})", "([^"]+)"\)/g)].map((m) => [m[1], m[2]]);
  assert.deepEqual(pairs, Object.entries(LANG_NAMES));
});

test('keyboard MODE out writes the TARGET language, the English-only lines only for English', () => {
  const out = prompt.slice(prompt.indexOf('\nMODE out '), prompt.indexOf('\nMODE fix '));
  const english = out.indexOf('\nIf TARGET is English:\n');
  const other = out.indexOf('\nAny other TARGET: ');
  for (const line of [TRANSLATE_TONE, 'ㅠㅠ becomes :( or words']) {
    const at = out.indexOf(line);
    assert.ok(english >= 0 && english < at && at < other, line);
  }
  assert.match(out, /into the TARGET language/);
  assert.match(out, /Russian past tense, Spanish or French adjectives/);
  assert.match(out, /ty spasla, never ty spas/);
  assert.match(other >= 0 ? out.slice(other) : '', /add nothing the DRAFT lacks/);
  // The user's style stays under its English header; a Korean polish stays Korean.
  assert.match(prompt, /^English you write in MODE out and MODE fix:$/m);
  assert.match(prompt, /A Korean DRAFT stays Korean, with its speech level, ㅋㅋ and ㅠㅠ\./);
});

test('keyboard prompt has no screen or memo material from the Shortcut prompt', () => {
  assert.doesNotMatch(prompt, /screenshot|screen|memo|PEOPLE/i);
});
