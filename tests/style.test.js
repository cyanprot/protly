import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ENGLISH_STYLE, POLISH_VOICE } from '../src/lib/style.js';
import { buildPolishRequest, buildOutgoingRequest, buildEmailRequest, buildBoxRequest } from '../src/lib/prompts.js';

const outgoing = (lang) => buildOutgoingRequest({ model: 'claude-opus-5-5', profile: 'outgoing', memo: '', context: [], korean: 'x', lang }).system;
const box = (lang) => buildBoxRequest({ model: 'claude-opus-5-5', korean: 'x', lang, hostname: 'example.com' }).system;
const polish = buildPolishRequest({ model: 'claude-opus-5-5', draft: 'x' }).system;
const email = buildEmailRequest({ model: 'claude-opus-5-5', context: [], korean: 'x' }).system;

test('English output carries the shared style; only Polish gets the dry voice', () => {
  for (const [name, s] of Object.entries({ polish, email, outgoing: outgoing('en'), box: box('en') })) {
    assert.ok(s.includes(ENGLISH_STYLE), name);
  }
  assert.ok(polish.includes(POLISH_VOICE));
  for (const s of [email, outgoing('en'), box('en')]) assert.equal(s.includes(POLISH_VOICE), false);
});

test('a non-English target keeps the prompt without the English style', () => {
  for (const s of [outgoing('ru'), box('ja')]) {
    assert.equal(s.includes(ENGLISH_STYLE), false);
    assert.match(s, /writer is male/);
  }
});

test('the style keeps the guide rules the eval checks', () => {
  assert.match(ENGLISH_STYLE, /Canadian spelling/);
  assert.match(ENGLISH_STYLE, /never an em dash, en dash, semicolon or slash/);
  for (const phrase of ['delve', 'additionally', 'I hope this finds you well', 'thank you for your time', 'touching base']) {
    assert.ok(ENGLISH_STYLE.includes(phrase), phrase);
  }
});

test('the style text breaks none of its own punctuation rules', () => {
  // Prompts are written in the target style: the model copies what it reads.
  assert.doesNotMatch(ENGLISH_STYLE + POLISH_VOICE, /[\u2013\u2014;]/);
});
