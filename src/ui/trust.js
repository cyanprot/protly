// Page scripts share the DOM with protly's controls that live in it (the Gmail Translate button) and can dispatch
// synthetic clicks on them. Only the user's own events, which the browser marks isTrusted, may act.
let trustAll = false;
export const trusted = (e) => trustAll || e?.isTrusted === true;

// Tests only: jsdom never marks an event trusted. This module instance lives in the extension's isolated world,
// so a page that imports the file gets its own copy and cannot flip protly's.
export function _trustSyntheticEvents(on = true) { trustAll = on; }
