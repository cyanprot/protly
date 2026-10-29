// Bundle entry for the any-site path (dist/generic.js). The fonts are inlined as Uint8Arrays by esbuild's binary
// loader. Re-injection keeps the live instance: one Esc listener, one card, fonts added once.
import regular from '../ui/fonts/protly-mono-400.woff2';
import medium from '../ui/fonts/protly-mono-500.woff2';
import { createInstance } from './instance.js';

// The key is a registered symbol, which window's named access (an element with an id or name) can never produce.
// background.js reads the same key in its executeScript funcs. The function check stays as a second guard.
const KEY = Symbol.for('protly');
if (typeof globalThis[KEY]?.run !== 'function') {
  globalThis[KEY] = createInstance({ doc: document, fonts: { regular, medium } });
}
