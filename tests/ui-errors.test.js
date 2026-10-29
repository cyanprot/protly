import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ERRORS, GLOBAL_KINDS, errorText } from '../src/ui/errors.js';

test('every ApiError kind has a message', () => {
  for (const k of ['auth', 'host', 'host_bug', 'timeout', 'spend_limit', 'rate', 'overloaded', 'server',
    'bad_request', 'network', 'refused', 'parse', 'truncated', 'stale']) {
    assert.equal(typeof ERRORS[k], 'string', k);
  }
});

test('errorText: table text, detail only for host_bug and bad_request, raw message otherwise', () => {
  assert.equal(errorText({ kind: 'timeout', message: 'x' }), ERRORS.timeout);
  assert.equal(errorText({ kind: 'bad_request', message: 'model not found' }), `${ERRORS.bad_request}: model not found`);
  assert.equal(errorText({ kind: 'host_bug', message: 'KeyError' }), `${ERRORS.host_bug}: KeyError`);
  assert.equal(errorText({ kind: 'internal', message: 'boom' }), 'boom');
  assert.equal(errorText(new Error('plain')), 'plain');
  assert.equal(errorText(null), 'Unknown error');
});

test('GLOBAL_KINDS are the page-wide problems', () => {
  assert.deepEqual([...GLOBAL_KINDS].sort(), ['auth', 'bad_message', 'bad_request', 'forbidden', 'host', 'host_bug', 'spend_limit', 'stale']);
});
