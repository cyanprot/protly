// A minimal fake of the chrome.* APIs that src/background.js touches at import and in its message handler.
// Not a test file itself (the runner picks up tests/*.test.js only).
export const EXT_ID = 'abcdefghijklmnopabcdefghijklmnop';
export const EXT_ORIGIN = `chrome-extension://${EXT_ID}`;

function fakeArea() {
  let data = {};
  const pick = (keys) => {
    if (keys == null) return { ...data };
    const list = Array.isArray(keys) ? keys : [keys];
    return Object.fromEntries(list.filter((k) => Object.hasOwn(data, k)).map((k) => [k, structuredClone(data[k])]));
  };
  return {
    get: async (keys) => pick(keys),
    set: async (obj) => { for (const [k, v] of Object.entries(obj)) data[k] = structuredClone(v); },
    remove: async (keys) => { for (const k of [].concat(keys)) delete data[k]; },
    dump: () => data,
    reset: () => { data = {}; },
  };
}

function event() {
  const fns = [];
  return { addListener: (f) => fns.push(f), removeListener: () => {}, fns };
}

// A fake native port. reply(fn) sets how the host answers each posted message.
function fakeNative() {
  const state = { sent: [], replyWith: null, ports: 0 };
  const connect = () => {
    state.ports++;
    const onMessage = event();
    const onDisconnect = event();
    return {
      onMessage, onDisconnect,
      postMessage(m) {
        state.sent.push(m);
        const r = state.replyWith?.(m);
        if (r) queueMicrotask(() => onMessage.fns.forEach((f) => f({ id: m.id, ...r })));
      },
    };
  };
  return { state, connect };
}

export function installFakeChrome() {
  const local = fakeArea();
  const session = fakeArea();
  const native = fakeNative();
  const onMessage = event();
  const badges = [];
  const chrome = {
    storage: { local, session, onChanged: event() },
    runtime: {
      id: EXT_ID,
      lastError: undefined,
      connectNative: native.connect,
      getURL: (p) => `${EXT_ORIGIN}/${p}`,
      onMessage, onInstalled: event(), onStartup: event(),
    },
    action: { setBadgeText: async (b) => { badges.push(b); } },
    commands: { onCommand: event() },
    contextMenus: { removeAll: (cb) => cb?.(), create: () => {}, onClicked: event() },
    tabs: { onUpdated: event(), onRemoved: event(), sendMessage: async () => undefined },
    scripting: { executeScript: async () => [] },
  };
  globalThis.chrome = chrome;

  // Sends one message the way Chrome does and resolves the response, or NO_RESPONSE when the listener declines.
  const send = (msg, sender) => new Promise((resolve) => {
    let answered = false;
    const reply = (r) => { answered = true; resolve(r); };
    const keepOpen = onMessage.fns.map((f) => f(msg, sender, reply)).some((x) => x === true);
    if (!keepOpen && !answered) resolve(NO_RESPONSE);
  });

  return { chrome, local, session, native: native.state, badges, send };
}

export const NO_RESPONSE = Symbol('no response');

// Senders as Chrome reports them. Content scripts carry a tab and the frame's origin; extension pages carry the
// extension origin (the options page runs in a tab, the popup does not).
export const senders = {
  popup: { id: EXT_ID, url: `${EXT_ORIGIN}/popup/popup.html`, origin: EXT_ORIGIN },
  options: { id: EXT_ID, url: `${EXT_ORIGIN}/options/options.html`, origin: EXT_ORIGIN, tab: { id: 9 }, frameId: 0 },
  instagram: { id: EXT_ID, url: 'https://www.instagram.com/direct/t/123/', origin: 'https://www.instagram.com', tab: { id: 1 }, frameId: 0 },
  gmail: { id: EXT_ID, url: 'https://mail.google.com/mail/u/0/#inbox', origin: 'https://mail.google.com', tab: { id: 2 }, frameId: 0 },
  page: { id: EXT_ID, url: 'https://evil.example/x', origin: 'https://evil.example', tab: { id: 3 }, frameId: 0 },
  otherExtension: { id: 'ponmlkjihgfedcbaponmlkjihgfedcba', url: 'chrome-extension://ponmlkjihgfedcbaponmlkjihgfedcba/x.html', origin: 'chrome-extension://ponmlkjihgfedcbaponmlkjihgfedcba' },
};

// A 2xx Messages API body whose text block is the JSON the parsers expect.
export const apiReply = (obj, extra = {}) => ({
  status: 200, retry_after: null,
  body: { model: 'claude-opus-5-5', stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(obj) }], usage: { input_tokens: 1, output_tokens: 1 }, ...extra },
});
