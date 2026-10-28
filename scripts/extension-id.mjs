import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Chrome's extension ID: SHA-256 of the DER public key, first 16 bytes, each hex digit 0-f mapped to a-p.
export function extensionId(keyB64) {
  const hex = createHash('sha256').update(Buffer.from(keyB64, 'base64')).digest('hex').slice(0, 32);
  return [...hex].map((c) => String.fromCharCode(97 + parseInt(c, 16))).join('');
}

// Run directly: print the ID that manifest.json's key pins.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const m = JSON.parse(readFileSync(new URL('../manifest.json', import.meta.url), 'utf8'));
  if (!m.key) { console.error('manifest.json has no key'); process.exit(1); }
  console.log(extensionId(m.key));
}
