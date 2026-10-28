import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decideBox, decideSelection } from '../src/generic/decide.js';

test('decideBox: a prefix translates the rest, whatever its script', () => {
  assert.deepEqual(decideBox('ru: 안녕'), { kind: 'translate', lang: 'ru', text: '안녕' });
  assert.deepEqual(decideBox('ja: see you tomorrow'), { kind: 'translate', lang: 'ja', text: 'see you tomorrow' });
});

test('decideBox: a prefix with nothing after it does nothing', () => {
  assert.deepEqual(decideBox('ru:   '), { kind: 'none' });
});

test('decideBox: Hangul goes to English', () => {
  assert.deepEqual(decideBox('내일 봐 ㅋㅋ'), { kind: 'translate', lang: 'en', text: '내일 봐 ㅋㅋ' });
});

test('decideBox: other letters are polished', () => {
  assert.deepEqual(decideBox('i has a question'), { kind: 'polish', text: 'i has a question' });
  assert.deepEqual(decideBox('привет как дела'), { kind: 'polish', text: 'привет как дела' });
});

test('decideBox: no letters, nothing to do', () => {
  for (const s of ['', '   ', '123 🙂', '!!!']) assert.deepEqual(decideBox(s), { kind: 'none' });
});

test('decideSelection', () => {
  assert.equal(decideSelection('안녕하세요'), 'already-ko');
  assert.equal(decideSelection('hello'), 'translate');
  assert.equal(decideSelection('hello 안녕'), 'translate');
  assert.equal(decideSelection('  '), 'none');
  assert.equal(decideSelection('123'), 'none');
});
