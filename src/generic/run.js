// Bundle entry for the any-site path (dist/generic.js). The fonts are inlined as Uint8Arrays by esbuild's binary
// loader. Re-injection keeps the live instance: one Esc listener, one card, fonts added once.
import regular from '../ui/fonts/protly-mono-400.woff2';
import medium from '../ui/fonts/protly-mono-500.woff2';
import { createInstance } from './instance.js';

globalThis.__protly ??= createInstance({ doc: document, fonts: { regular, medium } });
