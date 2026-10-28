import { test } from 'node:test';
import assert from 'node:assert/strict';
import { routeCommand } from '../src/lib/route.js';

function fakes({ answer, refuse = [] } = {}) {
  const log = [];
  return {
    log,
    deps: {
      sendToTab: async (tabId, msg, frameId) => {
        log.push(['send', tabId, msg.type, frameId]);
        if (answer instanceof Error) throw answer;
        return answer;
      },
      injectFile: async (tabId, frameId) => {
        log.push(['inject', tabId, frameId]);
        if (refuse.includes(frameId)) throw new Error('Cannot access contents of the page');
      },
      runGeneric: async (tabId, frameId, args) => { log.push(['run', tabId, frameId, args]); },
      setBadge: async (tabId, text, reason) => { log.push(['badge', tabId, text, reason]); },
      toastInMain: async (tabId, text) => { log.push(['toast', tabId, text]); },
    },
  };
}
const args = { source: 'command' };

test('an adapter that answers handled keeps the command', async () => {
  const { log, deps } = fakes({ answer: { handled: true } });
  assert.equal(await routeCommand({ tabId: 7, frameId: 0, args, ...deps }), 'adapter');
  assert.deepEqual(log, [['send', 7, 'command', 0]]);
});

for (const [name, answer] of [
  ['no receiver (sendMessage rejects)', new Error('Could not establish connection. Receiving end does not exist.')],
  ['no answer (undefined)', undefined],
  ['handled false', { handled: false }],
]) {
  test(`${name}: inject the generic bundle and run it in the same frame`, async () => {
    const { log, deps } = fakes({ answer });
    assert.equal(await routeCommand({ tabId: 7, frameId: 3, args, ...deps }), 'generic');
    assert.deepEqual(log.slice(1), [['inject', 7, 3], ['run', 7, 3, args]]);
  });
}

test('main frame refused: badge only', async () => {
  const { log, deps } = fakes({ refuse: [0] });
  assert.equal(await routeCommand({ tabId: 7, frameId: 0, args, ...deps }), 'unavailable');
  assert.deepEqual(log.slice(1), [['inject', 7, 0], ['badge', 7, '!', 'unavailable here']]);
});

// The page itself still works, so no badge: the popup must not say "Unavailable here" for the whole tab.
test('cross-origin frame refused: a toast from the main frame, no badge', async () => {
  const { log, deps } = fakes({ refuse: [5] });
  assert.equal(await routeCommand({ tabId: 7, frameId: 5, args, ...deps }), 'unavailable');
  assert.deepEqual(log.slice(1), [
    ['inject', 7, 5], ['inject', 7, 0], ['toast', 7, 'protly cannot reach this frame.'],
  ]);
});

test('frame and main frame both refused: badge, no toast, no throw', async () => {
  const { log, deps } = fakes({ refuse: [5, 0] });
  assert.equal(await routeCommand({ tabId: 7, frameId: 5, args, ...deps }), 'unavailable');
  assert.equal(log.some(([k]) => k === 'toast'), false);
  assert.ok(log.some(([k]) => k === 'badge'));
});

test('a failure inside the generic run is still routed to generic', async () => {
  const { deps } = fakes();
  deps.runGeneric = async () => { throw new Error('page threw'); };
  assert.equal(await routeCommand({ tabId: 7, frameId: 0, args, ...deps }), 'generic');
});

// Inside a Gmail or Instagram composer the adapter would answer handled and translate the whole draft.
test('translate selection skips the adapter, even when it would answer handled', async () => {
  const { log, deps } = fakes({ answer: { handled: true } });
  const sel = { source: 'menu-selection', selectionText: 'quoted text' };
  assert.equal(await routeCommand({ tabId: 7, frameId: 0, args: sel, ...deps }), 'generic');
  assert.deepEqual(log, [['inject', 7, 0], ['run', 7, 0, sel]]);
});
