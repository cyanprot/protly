import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, reduce } from '../src/lib/preview.js';

const run = (events, s = initial()) => {
  const effects = [];
  for (const e of events) { const r = reduce(s, e); s = r.state; effects.push(r.effect); }
  return { s, effects };
};

// idle -> translating -> preview for `korean`, returns the preview state
function toPreview(korean, { hard = false, lang = 'en' } = {}) {
  const a = reduce(initial(), { type: 'enter', text: korean, hard });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'T', back_translation: korean, lang, model: 'claude-sonnet-5-5' });
  return b.state;
}

test('non-Hangul Enter passes through', () => {
  const { s, effects } = run([{ type: 'enter', text: 'hello', hard: false }]);
  assert.equal(s.mode, 'idle');
  assert.deepEqual(effects[0], { type: 'pass' });
});

test('Hangul Enter starts translation; second Enter while pending is blocked', () => {
  const { s, effects } = run([
    { type: 'enter', text: '내일 봐', hard: false },
    { type: 'enter', text: '내일 봐', hard: false },
  ]);
  assert.equal(s.mode, 'translating');
  assert.equal(effects[0].type, 'translate');
  assert.equal(effects[0].korean, '내일 봐');
  assert.equal(effects[0].profile, 'outgoing');
  assert.equal(effects[0].lang, null);
  assert.deepEqual(effects[1], { type: 'block' });
});

test('result shows preview with model; Enter sends with Korean original', () => {
  const a = reduce(initial(), { type: 'enter', text: '내일 봐', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'see u tmrw', back_translation: '내일 봐', lang: 'en', model: 'claude-sonnet-5-5' });
  assert.equal(b.state.mode, 'preview');
  assert.deepEqual(b.effect, { type: 'show', translation: 'see u tmrw', back_translation: '내일 봐', profile: 'outgoing', lang: 'en', model: 'claude-sonnet-5-5' });
  const c = reduce(b.state, { type: 'enter', text: 'see u tmrw!', hard: false });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'sent', korean: '내일 봐' });
});

test('stale result is ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId + 99, translation: 'x', back_translation: 'y', lang: 'en', model: 'm' });
  assert.equal(b.state.mode, 'translating');
  assert.deepEqual(b.effect, { type: 'none' });
});

test('Alt+Enter outside preview uses hard profile', () => {
  const { effects } = run([{ type: 'enter', text: '가자', hard: true }]);
  assert.equal(effects[0].profile, 'hard');
});

test('Alt+Enter inside preview re-translates stored Korean with hard', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: "let's go (edited)", hard: true });
  assert.equal(c.state.mode, 'translating');
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.korean, '가자');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'en');
});

test('Hangul Enter in preview starts a new translation of the new text', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: '밥 먹자', hard: false });
  assert.equal(c.state.mode, 'translating');
  assert.equal(c.state.korean, '밥 먹자');
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.korean, '밥 먹자');
  assert.equal(c.effect.profile, 'outgoing');
  assert.equal(c.effect.lang, null);
});

test('Hangul Enter in preview with a Korean target sends', () => {
  const p = toPreview('가자', { lang: 'ko' });
  const c = reduce(p, { type: 'enter', text: '가자고', hard: false });
  assert.deepEqual(c.effect, { type: 'sent', korean: '가자' });
});

test('language change in preview re-translates with same profile', () => {
  const p = toPreview('가자', { hard: true });
  const c = reduce(p, { type: 'lang', lang: 'ru' });
  assert.equal(c.effect.type, 'translate');
  assert.equal(c.effect.profile, 'hard');
  assert.equal(c.effect.lang, 'ru');
  assert.equal(c.effect.korean, '가자');
});

test('Esc in preview restores Korean', () => {
  const c = reduce(toPreview('가자'), { type: 'esc' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'restore', korean: '가자' });
});

test('Esc while translating restores Korean; late result ignored', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'esc' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'restore', korean: '가자' });
  const c = reduce(b.state, { type: 'result', reqId: a.effect.reqId, translation: 'go', back_translation: '가자', lang: 'en', model: 'm' });
  assert.equal(c.state.mode, 'idle');
  assert.deepEqual(c.effect, { type: 'none' });
});

test('failure returns to idle and carries the Korean', () => {
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  const b = reduce(a.state, { type: 'fail', reqId: a.effect.reqId, message: 'overloaded' });
  assert.equal(b.state.mode, 'idle');
  assert.deepEqual(b.effect, { type: 'fail', message: 'overloaded', korean: '가자' });
});

test('failed re-translate from preview still carries the Korean', () => {
  const p = toPreview('가자');
  const c = reduce(p, { type: 'enter', text: 'T', hard: true });
  const d = reduce(c.state, { type: 'fail', reqId: c.effect.reqId, message: 'host' });
  assert.deepEqual(d.effect, { type: 'fail', message: 'host', korean: '가자' });
});

test('Esc in idle passes; reset always returns idle', () => {
  assert.deepEqual(reduce(initial(), { type: 'esc' }).effect, { type: 'pass' });
  const a = reduce(initial(), { type: 'enter', text: '가자', hard: false });
  assert.equal(reduce(a.state, { type: 'reset' }).state.mode, 'idle');
});

test('preview Enter sends a translation that keeps Hangul (ㅋㅋ, names)', () => {
  const a = reduce(initial(), { type: 'enter', text: 'ㅋㅋㅋ 내일 보자', hard: false });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'ㅋㅋ see u tmrw', back_translation: 'ㅋㅋ 내일 봐', lang: 'en', model: 'm' });
  const c = reduce(b.state, { type: 'enter', text: ' ㅋㅋ  see u tmrw ', hard: false });
  assert.deepEqual(c.effect, { type: 'sent', korean: 'ㅋㅋㅋ 내일 보자' });
  assert.equal(c.state.mode, 'idle');
});

test('preview Enter with different Hangul text is a new draft', () => {
  const s = toPreview('내일 봐');
  const r = reduce(s, { type: 'enter', text: '아니 모레 봐', hard: false });
  assert.equal(r.effect.type, 'translate');
  assert.equal(r.effect.korean, '아니 모레 봐');
});

// Polish (English drafts, toolbar toggle) and the language prefix.
const polishPreview = (text = 'i think its good') => {
  const a = reduce(initial(), { type: 'enter', text, polish: true });
  return reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'I think it is good.', back_translation: '수정', model: 'claude-sonnet-5-5' }).state;
};

test('English Enter: passes with polish off, starts a polish with it on', () => {
  assert.equal(reduce(initial(), { type: 'enter', text: 'hi there' }).effect.type, 'pass');
  const r = reduce(initial(), { type: 'enter', text: 'hi there', polish: true });
  assert.equal(r.effect.type, 'translate');
  assert.equal(r.effect.kind, 'polish');
  assert.equal(r.effect.korean, 'hi there');
  assert.equal(r.effect.profile, 'outgoing');
});

test('a draft with no letters passes even with polish on', () => {
  for (const t of ['😂😂', '12:30']) assert.equal(reduce(initial(), { type: 'enter', text: t, polish: true }).effect.type, 'pass');
});

test('polish preview: lang stays null, Enter sends, an edit is sent as is', () => {
  const s = polishPreview();
  assert.equal(s.mode, 'preview');
  assert.equal(s.lang, null);
  assert.deepEqual(reduce(s, { type: 'enter', text: 'I think it is good.', polish: true }).effect, { type: 'sent', korean: 'i think its good' });
  assert.equal(reduce(s, { type: 'enter', text: 'I think it is great.', polish: true }).effect.type, 'sent');
});

test('polish preview: Esc restores the English original, Alt+Enter re-polishes with hard', () => {
  const s = polishPreview();
  assert.deepEqual(reduce(s, { type: 'esc' }).effect, { type: 'restore', korean: 'i think its good' });
  const h = reduce(s, { type: 'enter', text: 'I think it is good.', hard: true, polish: true }).effect;
  assert.equal(h.kind, 'polish');
  assert.equal(h.profile, 'hard');
  assert.equal(h.korean, 'i think its good');
});

test('Hangul typed over a polish preview starts a translation', () => {
  const r = reduce(polishPreview(), { type: 'enter', text: '내일 보자', polish: true });
  assert.equal(r.effect.kind, 'translate');
  assert.equal(r.effect.korean, '내일 보자');
});

test('prefix: ru: picks the language for the request, Esc restores the prefixed draft', () => {
  const a = reduce(initial(), { type: 'enter', text: 'ru: 안녕' });
  assert.equal(a.effect.lang, 'ru');
  assert.equal(a.effect.korean, '안녕');
  assert.equal(a.state.korean, 'ru: 안녕');
  assert.deepEqual(reduce(a.state, { type: 'esc' }).effect, { type: 'restore', korean: 'ru: 안녕' });
});

test('prefix: the chip overrides it', () => {
  const a = reduce(initial(), { type: 'enter', text: 'ru: 안녕' });
  const b = reduce(a.state, { type: 'result', reqId: a.effect.reqId, translation: 'Привет', back_translation: '안녕', lang: 'ru', model: 'm' });
  const c = reduce(b.state, { type: 'lang', lang: 'ja' });
  assert.equal(c.effect.lang, 'ja');
  assert.equal(c.effect.korean, '안녕');
});

test('run in idle: Hangul translates without sending, like Enter', () => {
  const { s, effects } = run([{ type: 'run', text: '내일 봐' }]);
  assert.equal(s.mode, 'translating');
  assert.equal(effects[0].type, 'translate');
  assert.equal(effects[0].kind, 'translate');
  assert.equal(effects[0].profile, 'outgoing');
  assert.equal(effects[0].korean, '내일 봐');
});

test('run in idle: a prefix picks the language', () => {
  const { effects } = run([{ type: 'run', text: 'ru: 안녕' }]);
  assert.equal(effects[0].lang, 'ru');
  assert.equal(effects[0].korean, '안녕');
});

test('run in idle: English is polished whatever the polish toggle says', () => {
  const { s, effects } = run([{ type: 'run', text: 'i has a question' }]);
  assert.equal(s.mode, 'translating');
  assert.equal(effects[0].kind, 'polish');
  assert.equal(effects[0].profile, 'outgoing');
  assert.equal(effects[0].korean, 'i has a question');
});

test('run in idle: no letters does nothing', () => {
  const { s, effects } = run([{ type: 'run', text: '123 🙂' }]);
  assert.equal(s.mode, 'idle');
  assert.deepEqual(effects[0], { type: 'none' });
});

test('run is ignored while translating and in preview', () => {
  const a = reduce(initial(), { type: 'run', text: '내일 봐' });
  const b = reduce(a.state, { type: 'run', text: '내일 봐' });
  assert.equal(b.state, a.state);
  assert.deepEqual(b.effect, { type: 'none' });
  const p = toPreview('내일 봐');
  const c = reduce(p, { type: 'run', text: 'T' });
  assert.equal(c.state, p);
  assert.deepEqual(c.effect, { type: 'none' });
});
