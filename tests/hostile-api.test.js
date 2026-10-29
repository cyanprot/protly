// Malformed and hostile Messages API bodies: every parser fails as ApiError('parse') (one re-request, a readable
// message), never as a TypeError, and model-chosen ids or language codes never corrupt objects or stored state.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseIncoming, parseOutgoing, parseMemo, parseEmail } from '../src/lib/prompts.js';
import { callJson } from '../src/lib/api.js';

const textBody = (text) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text }] });
const MALFORMED = [
  null, undefined, 42, 'text', [], {},
  { content: null }, { content: 'a string' }, { content: { type: 'text', text: '{}' } },
  { content: [null] }, { content: [42, 'x'] }, { content: [{ type: 'text', text: null }] },
  { content: [{ type: 'text', text: { a: 1 } }] },
  textBody('null'), textBody('42'), textBody('"str"'), textBody('[]'), textBody('true'), textBody(''),
  textBody('<script>alert(1)</script>'),
  textBody('{"items": null}'), textBody('{"items": [null]}'), textBody('{"items": [42]}'), textBody('{"items": "x"}'),
  textBody('{"translation": null, "back_translation": "x"}'), textBody('{"memo": 5}'),
];

test('every parser turns a malformed body into ApiError parse', () => {
  for (const parse of [parseIncoming, parseOutgoing, parseMemo, parseEmail]) {
    for (const body of MALFORMED) {
      assert.throws(() => parse(body), (e) => e.kind === 'parse', `${parse.name} ${JSON.stringify(body)}`);
    }
  }
});

test('a malformed body gets the one re-request, like any unparseable reply', async () => {
  for (const body of [null, { content: 'x' }, textBody('null'), textBody('{"items":[null]}')]) {
    let calls = 0;
    const transport = async () => { calls++; return { status: 200, retry_after: null, body }; };
    await assert.rejects(callJson({}, parseIncoming, { transport, sleep: async () => {} }), (e) => e.kind === 'parse');
    assert.equal(calls, 2, JSON.stringify(body));
  }
});

test('model-chosen item ids are plain keys: __proto__ does not replace the prototype', () => {
  const out = parseIncoming(textBody(JSON.stringify({ items: [
    { id: '__proto__', src_lang: 'en', translation: 'polluted' },
    { id: 'constructor', src_lang: 'en', translation: 'c' },
    { id: '0', src_lang: 'en', translation: '안녕' },
  ] })));
  assert.equal(Object.getPrototypeOf(out), Object.prototype);
  assert.equal(out.translation, undefined);
  assert.deepEqual(Object.keys(out).sort(), ['0', '__proto__', 'constructor']);
  assert.equal(out['0'].translation, '안녕');
  assert.equal(({}).translation, undefined);
});

test('a non-text block or a text block with markup stays text', () => {
  const r = parseOutgoing({ stop_reason: 'end_turn', content: [
    { type: 'thinking', thinking: '{"translation":"wrong"}' },
    { type: 'text', text: JSON.stringify({ translation: '<img src=x onerror=alert(1)>', back_translation: '<b>안녕</b>' }) },
  ] });
  assert.equal(r.translation, '<img src=x onerror=alert(1)>');
  assert.equal(r.back_translation, '<b>안녕</b>');
});
