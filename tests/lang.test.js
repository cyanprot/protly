import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hasHangul, isKoreanOnly, incomingTarget, resolveOutputLang, latestPartnerLang } from '../src/lib/lang.js';

test('hasHangul', () => {
  assert.equal(hasHangul('hello'), false);
  assert.equal(hasHangul('ㅋㅋ ok'), true);
  assert.equal(hasHangul('안녕'), true);
});

test('isKoreanOnly ignores emoji, digits, punctuation', () => {
  assert.equal(isKoreanOnly('안녕 ㅋㅋ 😂 3시!'), true);
  assert.equal(isKoreanOnly('안녕 hi'), false);
  assert.equal(isKoreanOnly('😂'), false);
  assert.equal(isKoreanOnly('привет'), false);
});

test('incomingTarget', () => {
  assert.equal(incomingTarget('ko', 'en'), null);
  assert.equal(incomingTarget('en', 'en'), 'ko');
  assert.equal(incomingTarget('en', 'ko'), 'ko');
  assert.equal(incomingTarget('ru', 'en'), 'en');
  assert.equal(incomingTarget('ru', 'ko'), 'ko');
  assert.equal(incomingTarget('ja', 'ko'), 'ko');
});

test('resolveOutputLang', () => {
  assert.equal(resolveOutputLang({ outputLang: 'ru', partnerLang: 'en' }), 'ru');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: 'ru' }), 'ru');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: null }), 'en');
  assert.equal(resolveOutputLang({ outputLang: 'auto', partnerLang: 'ko' }), 'en');
});

test('latestPartnerLang picks last non-Korean partner message', () => {
  const r = [
    { from: 'partner', src_lang: 'en' },
    { from: 'me', src_lang: 'ru' },
    { from: 'partner', src_lang: 'ru' },
    { from: 'partner', src_lang: 'ko' },
  ];
  assert.equal(latestPartnerLang(r), 'ru');
  assert.equal(latestPartnerLang([]), null);
});

test('LANG_NAMES: lowercase codes, unique names, rest sorted by name', async () => {
  const { LANG_NAMES, langName } = await import('../src/lib/lang.js');
  const codes = Object.keys(LANG_NAMES);
  const names = Object.values(LANG_NAMES);
  assert.ok(codes.every((c) => /^[a-z]{2,3}$/.test(c)));
  assert.equal(new Set(names).size, names.length);
  const rest = names.slice(10);
  assert.deepEqual(rest, [...rest].sort());
  assert.equal(langName('vi'), 'Vietnamese');
  assert.equal(langName('xx'), 'xx');
});
