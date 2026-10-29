// The Instagram outgoing handler as mounted by the content script: main.js start() finds the thread and mounts
// outgoing.js, whose keydown listener is the one a page script's synthetic Enter reaches.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';

const PAGE = `<body>
  <nav><a href="/me"><img alt="me's profile picture"></a></nav>
  <div role="main"><form><div role="textbox" contenteditable="true"></div></form></div>
</body>`;

async function mountInstagram() {
  const win = new JSDOM(PAGE, { url: 'https://www.instagram.com/direct/t/123/' }).window;
  for (const k of ['window', 'document', 'location', 'MutationObserver', 'Option', 'Node', 'getComputedStyle']) {
    globalThis[k] = k === 'window' ? win : win[k];
  }
  const asked = [];
  let mounted;
  const isMounted = new Promise((r) => { mounted = r; });
  globalThis.chrome = {
    storage: { local: { get: async () => ({}) }, onChanged: { addListener() {} } },
    runtime: {
      id: 'protly',
      getURL: (p) => `chrome-extension://protly/${p}`,
      onMessage: { addListener: () => mounted(), removeListener() {} }, // outgoing.js registers its Alt+T listener
      sendMessage: (msg) => {
        asked.push(msg.type);
        if (msg.type === 'getThread') return Promise.resolve({ ok: true, data: { enabled: true, outputLang: 'auto', otherTarget: 'ko', pastMode: 'replace', newMode: 'below', memo: '' } });
        if (msg.type === 'outgoing' || msg.type === 'polish') return new Promise(() => {}); // a billed call: never answers here
        return Promise.resolve({ ok: true, data: true });
      },
    },
  };
  globalThis.fetch = async () => ({ ok: false, status: 404 }); // fonts: the monospace fallback
  const realSetInterval = globalThis.setInterval;
  globalThis.setInterval = (f, ms) => realSetInterval(f, ms).unref(); // the path poll must not keep the test alive
  const { start } = await import('../src/content/main.js');
  await start();
  await isMounted; // an empty thread is accepted after about 1 s
  const composer = win.document.querySelector('div[role="textbox"]');
  Object.defineProperty(composer, 'innerText', { get: () => composer.textContent }); // jsdom has no layout text
  return { win, asked, composer };
}

test('Instagram: a synthetic Enter on Hangul in the composer is held and asks for nothing', async () => {
  const { win, asked, composer } = await mountInstagram();
  const enter = () => new win.KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true, cancelable: true });
  let pageSaw = 0;
  composer.addEventListener('keydown', () => { pageSaw++; }); // Instagram's own send handler sits here
  composer.textContent = '안녕';
  composer.focus();
  asked.length = 0;

  const e = enter();
  assert.equal(e.isTrusted, false);
  composer.dispatchEvent(e);
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(e.defaultPrevented, true); // held, not passed through to Instagram
  assert.equal(pageSaw, 0);
  assert.deepEqual(asked.filter((t) => t === 'outgoing' || t === 'polish'), []); // nothing billed

  // Control: the same Enter from the user reaches the handler and starts a translation, so the hold above is the
  // guard's doing and not an unmounted handler.
  const { _trustSyntheticEvents } = await import('../src/ui/trust.js');
  _trustSyntheticEvents(true);
  try {
    const own = enter();
    composer.dispatchEvent(own);
    await new Promise((r) => setTimeout(r, 20));
    assert.equal(own.defaultPrevented, true);
    assert.deepEqual(asked.filter((t) => t === 'outgoing'), ['outgoing']);
  } finally {
    _trustSyntheticEvents(false);
  }
});
