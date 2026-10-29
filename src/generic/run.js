// Bundle entry for the any-site path (dist/generic.js). The fonts are inlined as Uint8Arrays by esbuild's binary
// loader. Re-injection keeps the live instance: one Esc listener, one card, fonts added once.
import regular from '../ui/fonts/protly-mono-400.woff2';
import medium from '../ui/fonts/protly-mono-500.woff2';
import { createInstance } from './instance.js';

// Only a real instance counts: an element with id or name "__protly" shows through window's named access.
if (typeof globalThis.__protly?.run !== 'function') {
  globalThis.__protly = createInstance({ doc: document, fonts: { regular, medium } });
}
