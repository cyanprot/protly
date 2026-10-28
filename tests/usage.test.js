import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  PRICES, KEEP_DAYS, tokensOf, costOf, localDate, createUsageRecorder, summarize, formatUsd,
} from '../src/lib/usage.js';

const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`);
const NOON_OCT_28 = new Date(2026, 9, 28, 12).getTime(); // local time, away from midnight and DST edges
const MILLION = { input: 1e6, output: 1e6, cache_read: 1e6, cache_5m: 1e6, cache_1h: 1e6 };

// In-memory storage whose reads and writes yield, so unserialized writers would lose increments.
function memStore(initial) {
  let value = initial;
  const tick = () => new Promise((r) => setTimeout(r, 0));
  return {
    get: async () => { await tick(); return value && structuredClone(value); },
    set: async (v) => { await tick(); value = structuredClone(v); },
    peek: () => value,
  };
}

test('price table matches the shared contract', () => {
  assert.deepEqual(PRICES['claude-sonnet-5-5'], { input: 2, output: 10, cache_read: 0.1, cache_5m: 2.5, cache_1h: 4 });
  assert.deepEqual(PRICES['claude-opus-5-5'], { input: 4, output: 20, cache_read: 0.2, cache_5m: 5, cache_1h: 8 });
  assert.equal(KEEP_DAYS, 62);
});

test('tokensOf uses the 5m/1h breakdown when the response gives it', () => {
  const t = tokensOf({
    usage: {
      input_tokens: 100, output_tokens: 50, cache_read_input_tokens: 10, cache_creation_input_tokens: 30,
      cache_creation: { ephemeral_5m_input_tokens: 20, ephemeral_1h_input_tokens: 10 },
    },
  });
  assert.deepEqual(t, { input: 100, output: 50, cache_read: 10, cache_5m: 20, cache_1h: 10 });
});

test('tokensOf counts all cache creation as 5m without a breakdown', () => {
  const t = tokensOf({ usage: { input_tokens: 1, output_tokens: 2, cache_creation_input_tokens: 30 } });
  assert.deepEqual(t, { input: 1, output: 2, cache_read: 0, cache_5m: 30, cache_1h: 0 });
});

test('tokensOf tolerates a body without usage', () => {
  assert.deepEqual(tokensOf({}), { input: 0, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0 });
  assert.deepEqual(tokensOf(undefined), { input: 0, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0 });
});

test('costOf prices every field; a dated model id uses its base price; unknown is null', () => {
  near(costOf(MILLION, 'claude-sonnet-5-5'), 2 + 10 + 0.1 + 2.5 + 4);
  near(costOf(MILLION, 'claude-opus-5-5-20261001'), 4 + 20 + 0.2 + 5 + 8);
  assert.equal(costOf(MILLION, 'claude-mystery-9'), null);
  assert.equal(costOf(MILLION, 'unknown'), null);
});

test('localDate is the local calendar day, zero padded', () => {
  assert.equal(localDate(new Date(2026, 0, 5, 23, 59).getTime()), '2026-01-05');
});

test('concurrent records are serialized: nothing is lost', async () => {
  const s = memStore(undefined);
  const rec = createUsageRecorder({ get: s.get, set: s.set, now: () => NOON_OCT_28 });
  const body = { model: 'claude-sonnet-5-5', usage: { input_tokens: 10, output_tokens: 1 } };
  await Promise.all(Array.from({ length: 10 }, () => rec.record(body)));
  const e = s.peek()['2026-10-28']['claude-sonnet-5-5'];
  assert.equal(e.calls, 10);
  assert.equal(e.input, 100);
  assert.equal(e.output, 10);
});

test('a failed write does not break later records', async () => {
  const s = memStore(undefined);
  let fail = true;
  const set = async (v) => { if (fail) { fail = false; throw new Error('quota'); } return s.set(v); };
  const rec = createUsageRecorder({ get: s.get, set, now: () => NOON_OCT_28 });
  await rec.record({ model: 'claude-sonnet-5-5', usage: { input_tokens: 1 } });
  await rec.record({ model: 'claude-sonnet-5-5', usage: { input_tokens: 2 } });
  assert.equal(s.peek()['2026-10-28']['claude-sonnet-5-5'].input, 2);
});

test('days older than 62 are pruned on write; day 62 is kept', async () => {
  const s = memStore({
    '2026-08-26': { 'claude-sonnet-5-5': { calls: 1, input: 1, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0 } },
    '2026-08-27': { 'claude-sonnet-5-5': { calls: 1, input: 1, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0 } },
  });
  const rec = createUsageRecorder({ get: s.get, set: s.set, now: () => NOON_OCT_28 });
  await rec.record({ model: 'claude-sonnet-5-5', usage: {} });
  assert.deepEqual(Object.keys(s.peek()).sort(), ['2026-08-27', '2026-10-28']);
});

test('a body without a model is recorded under "unknown"', async () => {
  const s = memStore(undefined);
  const rec = createUsageRecorder({ get: s.get, set: s.set, now: () => NOON_OCT_28 });
  await rec.record({ usage: { input_tokens: 5 } });
  assert.equal(s.peek()['2026-10-28'].unknown.input, 5);
});

test('summarize: today, this calendar month, and unpriced only within the month', () => {
  const e = (fields) => ({ calls: 1, input: 0, output: 0, cache_read: 0, cache_5m: 0, cache_1h: 0, ...fields });
  const usage = {
    '2026-10-28': { 'claude-sonnet-5-5': e({ input: 1e6 }) },
    '2026-10-01': { 'claude-opus-5-5': e({ output: 1e6 }) },
    '2026-09-30': { 'claude-sonnet-5-5': e({ output: 1e6 }), 'claude-mystery-9': e({ input: 1e6 }) },
  };
  const s = summarize(usage, NOON_OCT_28);
  near(s.today, 2);
  near(s.month, 22);
  assert.equal(s.unpriced, false);

  usage['2026-10-02'] = { 'claude-mystery-9': e({ input: 1e6 }) };
  const s2 = summarize(usage, NOON_OCT_28);
  near(s2.month, 22); // the unknown model adds nothing it cannot price
  assert.equal(s2.unpriced, true);
  assert.deepEqual(summarize({}, NOON_OCT_28), { today: 0, month: 0, unpriced: false });
});

test('formatUsd', () => {
  assert.equal(formatUsd(0), '$0.00');
  assert.equal(formatUsd(0.004), '<$0.01');
  assert.equal(formatUsd(1.234), '$1.23');
  assert.equal(formatUsd(1.234, true), '$1.23 ?');
});
