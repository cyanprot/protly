// Builds dist/generic.js, the any-site bundle injected with chrome.scripting.executeScript.
// One IIFE with the fonts inlined (the binary loader turns each .woff2 into a Uint8Array at run time), so nothing is
// web-accessible to arbitrary sites. target chrome120 keeps esbuild's own base64 decoder instead of
// Uint8Array.fromBase64, which node 22 (the jsdom test) lacks.
import { build } from 'esbuild';

await build({
  entryPoints: ['src/generic/run.js'],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'chrome120',
  outfile: 'dist/generic.js',
  loader: { '.woff2': 'binary' },
  legalComments: 'none',
  logLevel: 'warning',
});
