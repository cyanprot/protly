import { test } from 'node:test';
import { DEFAULT_SETTINGS } from '../src/lib/keys.js';
import assert from 'node:assert/strict';
import {
  PROFILES, thinkingFor, buildIncomingRequest, buildOutgoingRequest, buildMemoRequest,
  parseIncoming, parseOutgoing, parseMemo, buildBoxRequest, buildSelectionRequest,
} from '../src/lib/prompts.js';

const ctx = [{ from: 'partner', text: 'hey' }, { from: 'me', text: 'yo' }];

test('thinkingFor: Sonnet off = between_tools, Opus always adaptive', () => {
  assert.deepEqual(thinkingFor('claude-sonnet-5-5', true), { type: 'between_tools' });
  assert.deepEqual(thinkingFor('claude-opus-5-5', true), { type: 'adaptive' });
  assert.deepEqual(thinkingFor('claude-sonnet-5-5', false), { type: 'adaptive' });
});

test('incoming request shape', () => {
  const b = buildIncomingRequest({
    model: 'claude-sonnet-5-5', memo: 'old friend', context: ctx, otherTarget: 'en',
    items: [{ id: '0', text: 'привет' }],
  });
  assert.equal(b.model, 'claude-sonnet-5-5');
  assert.deepEqual(b.thinking, { type: 'between_tools' });
  assert.equal(b.output_config.effort, 'low');
  assert.equal(b.output_config.format.type, 'json_schema');
  assert.equal(b.max_tokens, PROFILES.incoming.max_tokens);
  for (const k of ['temperature', 'top_p', 'top_k']) assert.equal(k in b, false);
  const u = b.messages[0].content;
  assert.match(u, /TARGET_FOR_OTHER: English/);
  assert.match(u, /old friend/);
  assert.match(u, /FRIEND: hey/);
  assert.match(u, /ME: yo/);
  assert.match(u, /привет/);
});

test('outgoing request uses profile and target', () => {
  const b = buildOutgoingRequest({ model: 'claude-opus-5-5', profile: 'hard', memo: '', context: ctx, korean: '내일 보자', lang: 'ru' });
  assert.deepEqual(b.thinking, { type: 'adaptive' });
  assert.equal(b.output_config.effort, 'high');
  assert.match(b.messages[0].content, /TARGET: Russian/);
  assert.match(b.messages[0].content, /내일 보자/);

test('outgoing profile is low effort; Opus is the default model for drafts', () => {
  const b = buildOutgoingRequest({ model: 'claude-opus-5-5', profile: 'outgoing', memo: '', context: ctx, korean: '응', lang: 'en' });
  assert.equal(b.output_config.effort, 'low');
  assert.equal(DEFAULT_SETTINGS.models.outgoing, 'claude-opus-5-5');
  assert.equal(DEFAULT_SETTINGS.models.incoming, 'claude-sonnet-5-5');
});
});

test('memo request', () => {
  const b = buildMemoRequest({ model: 'claude-sonnet-5-5', context: ctx });
  assert.equal(b.output_config.effort, 'low');
  assert.match(b.messages[0].content, /FRIEND: hey/);
});

const resp = (text, stop = 'end_turn') => ({
  stop_reason: stop,
  content: [{ type: 'thinking', thinking: '' }, { type: 'text', text }],
});

test('parseIncoming maps ids and skips thinking blocks', () => {
  const r = parseIncoming(resp('{"items":[{"id":"0","src_lang":"ru","translation":"hi"}]}'));
  assert.deepEqual(r, { '0': { src_lang: 'ru', translation: 'hi' } });
});

test('parseIncoming normalizes src_lang to a bare lowercase code', () => {
  const r = parseIncoming(resp('{"items":[{"id":"0","src_lang":"ko-KR","translation":"x"},{"id":"1","src_lang":"EN","translation":"y"}]}'));
  assert.equal(r['0'].src_lang, 'ko');
  assert.equal(r['1'].src_lang, 'en');
});

test('parseOutgoing accepts JSON embedded in prose (no-format fallback)', () => {
  const r = parseOutgoing(resp('Here:\n{"translation":"see you","back_translation":"또 봐"}'));
  assert.deepEqual(r, { translation: 'see you', back_translation: '또 봐' });
});

test('parse errors', () => {
  assert.throws(() => parseOutgoing(resp('nope')), (e) => e.kind === 'parse');
  assert.throws(() => parseOutgoing(resp('{"translation":"x"}')), (e) => e.kind === 'parse');
  assert.throws(() => parseOutgoing(resp('{}', 'max_tokens')), (e) => e.kind === 'truncated');
  assert.throws(() => parseOutgoing(resp('{}', 'refusal')), (e) => e.kind === 'refused');
});

test('parseMemo', () => {
  assert.equal(parseMemo(resp('{"memo":"close friend, teases a lot"}')), 'close friend, teases a lot');
});

test('outgoing prompt fixes the writer as male', () => {
  const b = buildOutgoingRequest({ model: 'claude-sonnet-5-5', profile: 'outgoing', memo: '', context: [], korean: '피곤했어', lang: 'ru' });
  assert.match(b.system, /writer is male/);
});

test('parseIncoming drops empty translations so they are never cached', () => {
  const r = parseIncoming(resp('{"items":[{"id":"0","src_lang":"en","translation":"  "},{"id":"1","src_lang":"en","translation":"안녕"}]}'));
  assert.deepEqual(Object.keys(r), ['1']);
});

import { buildEmailRequest, parseEmail } from '../src/lib/prompts.js';

test('email request: auto target, thread roles, male writer, schema has lang', () => {
  const b = buildEmailRequest({
    model: 'claude-sonnet-5-5',
    context: [{ from: 'them', text: 'Dear Mr Kim' }, { from: 'me', text: 'Hello' }],
    korean: '확인했습니다',
  });
  assert.match(b.messages[0].content, /TARGET: auto/);
  assert.match(b.messages[0].content, /--- THEM:\nDear Mr Kim/);
  assert.match(b.messages[0].content, /KOREAN DRAFT:\n확인했습니다/);
  assert.match(b.system, /writer is male/);
  assert.deepEqual(b.output_config.format.schema.required, ['lang', 'translation', 'back_translation']);
  assert.equal(b.output_config.effort, 'low');
  assert.equal('temperature' in b, false);
});

test('email request: fixed language, no thread, Opus hard profile', () => {
  const b = buildEmailRequest({ model: 'claude-opus-5-5', profile: 'hard', context: [], korean: '네', lang: 'ru' });
  assert.match(b.messages[0].content, /TARGET: Russian/);
  assert.match(b.messages[0].content, /new email/);
  assert.equal(b.output_config.effort, 'high');
  assert.deepEqual(b.thinking, { type: 'adaptive' });
});

test('parseEmail normalizes lang and rejects an empty translation', () => {
  assert.deepEqual(
    parseEmail(resp('{"lang":"EN-us","translation":"Confirmed.","back_translation":"확인했습니다."}')),
    { lang: 'en', translation: 'Confirmed.', back_translation: '확인했습니다.' },
  );
  assert.throws(() => parseEmail(resp('{"lang":"en","translation":"  ","back_translation":"x"}')), (e) => e.kind === 'parse');
  assert.throws(() => parseEmail(resp('{}', 'max_tokens')), (e) => e.kind === 'truncated');
});

import { buildPolishRequest } from '../src/lib/prompts.js';

test('polish request: the user style rules, draft last, effort low; hard is Opus high', () => {
  const b = buildPolishRequest({ model: 'claude-sonnet-5-5', draft: 'i think its good' });
  assert.match(b.system, /Spelling: Canadian/);
  assert.match(b.system, /no em dash/);
  assert.match(b.system, /An email keeps its greeting/);
  assert.equal(b.messages[0].content, 'DRAFT:\ni think its good');
  assert.equal(b.output_config.effort, 'low');
  assert.deepEqual(b.output_config.format.schema.required, ['translation', 'back_translation']);
  const h = buildPolishRequest({ model: 'claude-opus-5-5', profile: 'hard', draft: 'x' });
  assert.equal(h.output_config.effort, 'high');
});

test('parseOutgoing rejects an empty translation', () => {
  assert.throws(() => parseOutgoing(resp('{"translation":"  ","back_translation":"x"}')), (e) => e.kind === 'parse');
});

test('outgoing prompt checks gendered words and never answers in Korean; email skips Korean for auto', () => {
  const o = buildOutgoingRequest({ model: 'claude-sonnet-5-5', profile: 'outgoing', memo: '', context: [], korean: '고마워', lang: 'ru' });
  assert.match(o.system, /ty spasla/);
  assert.match(o.system, /never Korean/);
  const e = buildEmailRequest({ model: 'claude-sonnet-5-5', context: [], korean: '네' });
  assert.match(e.system, /never Korean/);
  assert.match(e.system, /non-Korean message/);
  assert.doesNotMatch(e.system, /ty spasla/);
});

test('box request: outgoing system, hostname line, no memo or conversation', () => {
  const b = buildBoxRequest({ model: 'claude-sonnet-5-5', profile: 'outgoing', korean: '안녕하세요', lang: 'en', hostname: 'forum.example.org' });
  const dm = buildOutgoingRequest({ model: 'claude-sonnet-5-5', profile: 'outgoing', memo: '', context: [], korean: 'x', lang: 'en' });
  assert.equal(b.system, dm.system);
  assert.equal(b.output_config.effort, PROFILES.outgoing.effort);
  const u = b.messages[0].content;
  assert.match(u, /^TARGET: English/);
  assert.match(u, /This text goes into a text box on forum\.example\.org\. Keep the register the writer used/);
  assert.match(u, /KOREAN DRAFT:\n안녕하세요$/);
  assert.doesNotMatch(u, /THREAD MEMO|RECENT CONVERSATION/);
});

test('box request: hard profile and another language', () => {
  const b = buildBoxRequest({ model: 'claude-opus-5-5', profile: 'hard', korean: '안녕', lang: 'ru', hostname: 'x.test' });
  assert.equal(b.output_config.effort, PROFILES.hard.effort);
  assert.match(b.messages[0].content, /^TARGET: Russian/);
});

test('selection request: incoming prompt, Korean target, one item, no memo or context', () => {
  const b = buildSelectionRequest({ model: 'claude-sonnet-5-5', text: 'hello there' });
  assert.equal(b.output_config.effort, PROFILES.incoming.effort);
  const u = b.messages[0].content;
  assert.match(u, /TARGET_FOR_OTHER: Korean/);
  assert.match(u, /THREAD MEMO:\n\(none\)/);
  assert.match(u, /RECENT CONVERSATION \(oldest first\):\n\(none\)/);
  assert.match(u, /\[\{"id":"0","text":"hello there"\}\]/);
});
