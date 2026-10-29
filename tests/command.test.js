import { test } from 'node:test';
import assert from 'node:assert/strict';
import { commandListener } from '../src/lib/command.js';

const flush = () => new Promise((r) => setTimeout(r, 0));

function make({ owner = () => null, composing = () => false } = {}) {
  const ran = [];
  const settled = [];
  const listener = commandListener({
    owner, composing, run: (el) => ran.push(el),
    settle: async (el, opts) => { settled.push([el, opts]); },
  });
  return { listener, ran, settled };
}

test('not the command: no answer', () => {
  const { listener } = make({ owner: () => 'box' });
  let answered = false;
  assert.equal(listener({ type: 'badge' }, {}, () => { answered = true; }), false);
  assert.equal(answered, false);
});

test('focus outside the composer: no answer, nothing runs', async () => {
  const { listener, ran } = make();
  let answered = false;
  assert.equal(listener({ type: 'command' }, {}, () => { answered = true; }), false);
  await flush();
  assert.equal(answered, false);
  assert.equal(ran.length, 0);
});

test('owner throws: treated as not owned', () => {
  const { listener } = make({ owner: () => { throw new Error('selector'); } });
  assert.equal(listener({ type: 'command' }, {}, () => {}), false);
});

test('focused composer: answers handled at once, settles the IME, then runs', async () => {
  const { listener, ran, settled } = make({ owner: () => 'box', composing: () => true });
  const answers = [];
  listener({ type: 'command' }, {}, (r) => answers.push(r));
  assert.deepEqual(answers, [{ handled: true }]); // synchronous: the background does not wait for the API
  assert.equal(ran.length, 0);
  await flush();
  assert.deepEqual(settled, [['box', { composing: true }]]);
  assert.deepEqual(ran, ['box']);
});

test('odd messages never reach owner or sendResponse', async () => {
  const { commandListener } = await import('../src/lib/command.js');
  let owned = 0;
  let answered = 0;
  const l = commandListener({ owner: () => { owned++; return {}; }, composing: () => false, run: () => {}, settle: async () => {} });
  for (const msg of [null, undefined, 'command', 7, [], { type: ['command'] }, { type: 'Command' }, { type: 'command ' }]) {
    assert.equal(l(msg, {}, () => { answered++; }), false, JSON.stringify(msg));
  }
  assert.equal(owned, 0);
  assert.equal(answered, 0);
});
