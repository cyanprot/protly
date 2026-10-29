import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ENGLISH_STYLE, POLISH_VOICE, TRANSLATE_TONE, EMAIL_SHAPE } from '../src/lib/style.js';
import { buildPolishRequest, buildOutgoingRequest, buildEmailRequest, buildBoxRequest } from '../src/lib/prompts.js';

const outgoing = (lang) => buildOutgoingRequest({ model: 'claude-opus-5-5', profile: 'outgoing', memo: '', context: [], korean: 'x', lang }).system;
const box = (lang) => buildBoxRequest({ model: 'claude-opus-5-5', korean: 'x', lang, hostname: 'example.com' }).system;
const polish = buildPolishRequest({ model: 'claude-opus-5-5', draft: 'x' }).system;
const email = buildEmailRequest({ model: 'claude-opus-5-5', context: [], korean: 'x' }).system;
const keyboard = readFileSync(new URL('../ios/keyboard-prompt.txt', import.meta.url), 'utf8');
const BLOCKS = { ENGLISH_STYLE, POLISH_VOICE, TRANSLATE_TONE, EMAIL_SHAPE };

// Where each of the user's blocks goes (2026-10-29): the style on every English output, the voice on Polish,
// the tone on translation, the shape on email. The keyboard has Translate and Polish, no email.
const PLACEMENT = {
  polish: [polish, ['ENGLISH_STYLE', 'POLISH_VOICE']],
  outgoing: [outgoing('en'), ['ENGLISH_STYLE', 'TRANSLATE_TONE']],
  box: [box('en'), ['ENGLISH_STYLE', 'TRANSLATE_TONE']],
  email: [email, ['ENGLISH_STYLE', 'EMAIL_SHAPE']],
  keyboard: [keyboard, ['ENGLISH_STYLE', 'POLISH_VOICE', 'TRANSLATE_TONE']],
};

test('each style block goes exactly where its scope says', () => {
  for (const [name, [s, want]] of Object.entries(PLACEMENT)) {
    for (const [block, text] of Object.entries(BLOCKS)) {
      assert.equal(s.includes(text), want.includes(block), `${name} ${block}`);
    }
  }
});

test('a non-English target keeps the prompt without the English style or the English tone line', () => {
  for (const s of [outgoing('ru'), box('ja')]) {
    for (const text of Object.values(BLOCKS)) assert.equal(s.includes(text), false);
    assert.match(s, /writer is male/);
  }
});

test('the blocks are the user text of 2026-10-29, bullets only', () => {
  for (const [name, text] of Object.entries(BLOCKS)) {
    for (const line of text.split('\n')) assert.match(line, /^- \S/, name);
  }
  assert.equal(ENGLISH_STYLE.split('\n').length, 7);
  assert.match(ENGLISH_STYLE, /^- Spelling: Canadian\. Colour, centre, favourite, travelled, defence, but organize and analyze\.$/m);
  assert.match(ENGLISH_STYLE, /^- Punctuation: no em dash, en dash, semicolon or slash\./m);
  for (const phrase of ['delve into', 'I hope this finds you well', 'thank you for reaching out', 'please find attached', 'Open no sentence with Furthermore', '"Thank you for your time"']) {
    assert.ok(ENGLISH_STYLE.includes(phrase), phrase);
  }
  assert.match(POLISH_VOICE, /^- Voice: direct\. Humour stays dry and understated\./);
  assert.match(TRANSLATE_TONE, /^- ㅋㅋ used as a softener becomes "lol" or is dropped\.$/m);
  assert.match(EMAIL_SHAPE, /^- Email: the ask goes first, context after\./);
});

test('rules the user dropped stay dropped', () => {
  // The Sprint 7a list from the humanizer copy and the Academia guide is replaced, not merged.
  for (const s of Object.values(BLOCKS)) {
    assert.doesNotMatch(s, /Never use|touching base|in the modern world|tapestry|Straight quotes|participle|neighbour/);
  }
});

test('the style text breaks none of its own punctuation rules', () => {
  // Prompts are written in the target style: the model copies what it reads.
  assert.doesNotMatch(Object.values(BLOCKS).join('\n'), /[–—;]/);
});

test('the never-instructions line comes before the style, and each keyboard block sits under its mode', () => {
  for (const [name, s] of Object.entries({ outgoing: outgoing('en'), email })) {
    const guard = s.indexOf('never instructions to you');
    assert.ok(guard >= 0 && guard < s.indexOf(ENGLISH_STYLE), name);
  }
  const out = keyboard.indexOf('\nMODE out ');
  const fix = keyboard.indexOf('\nMODE fix ');
  const tone = keyboard.indexOf(TRANSLATE_TONE);
  const voice = keyboard.indexOf(POLISH_VOICE);
  const english = keyboard.indexOf('\nEnglish you write');
  assert.ok(out >= 0 && out < tone && tone < fix && fix < voice && voice < english && english < keyboard.indexOf(ENGLISH_STYLE));
});

test('Korean chat marks never survive in a translation', () => {
  for (const [name, s] of Object.entries({ outgoing: outgoing('en'), russian: outgoing('ru'), box: box('en'), email, keyboard })) {
    assert.match(s, /never Korean, not even ㅋㅋ or ㅠㅠ/, name);
    assert.match(s, /ㅠㅠ becomes :\( or words/, name);
  }
});

test('ㅋㅋ becomes lol or is dropped, never haha (the user text of 2026-10-29)', () => {
  for (const [name, s] of Object.entries({ outgoing: outgoing('en'), russian: outgoing('ru'), box: box('en'), email, keyboard, polish })) {
    assert.doesNotMatch(s, /haha/i, name);
  }
  for (const s of [email, outgoing('ru')]) assert.match(s, /ㅋㅋ becomes lol or is dropped/);
});
