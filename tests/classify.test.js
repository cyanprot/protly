import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyAdded } from '../src/lib/classify.js';

const known = (set) => (x) => set.has(x);

test('appended below last known = fresh, prepended above = past', () => {
  const r = classifyAdded(['h1', 'h2', 'a', 'b', 'n1'], known(new Set(['a', 'b'])));
  assert.deepEqual(r, { past: ['h1', 'h2'], fresh: ['n1'] });
});

test('unknown between known ones = past', () => {
  const r = classifyAdded(['a', 'x', 'b'], known(new Set(['a', 'b'])));
  assert.deepEqual(r, { past: ['x'], fresh: [] });
});

test('nothing known = all fresh (caller handles initial scan separately)', () => {
  assert.deepEqual(classifyAdded(['a', 'b'], known(new Set())), { past: [], fresh: ['a', 'b'] });
});
