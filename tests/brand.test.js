import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// keyboard-ui 003, Task 3.6: the brand lives in three copies (design D3). The extension's tokens are the source; the
// keyboard (Brand.swift) and the container app (ProtlyApp.swift, which does not link the keyboard) repeat them.
const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8');

const tokens = read('src/ui/tokens.css.js');

function cssHex(name) {
  const m = tokens.match(new RegExp(`--pl-${name}:\\s*#([0-9A-Fa-f]{6});`));
  assert.ok(m, `--pl-${name} not found in src/ui/tokens.css.js`);
  return m[1].toUpperCase();
}

function swiftHex(path, name) {
  const lines = read(path).split('\n').filter((l) => new RegExp(`\\bstatic let ${name}Hex\\b`).test(l));
  assert.equal(lines.length, 1, `${path}: expected one ${name}Hex line, found ${lines.length}`);
  const m = lines[0].match(new RegExp(`static let ${name}Hex\\s*=\\s*0x([0-9A-Fa-f]{6})\\s*$`));
  assert.ok(m, `${path}: ${name}Hex is not a 6-digit hex literal: ${lines[0].trim()}`);
  return m[1].toUpperCase();
}

for (const path of ['ios-app/Sources/ProtlyKeyboard/Brand.swift', 'ios-app/Sources/Protly/ProtlyApp.swift']) {
  for (const name of ['paper', 'ink']) {
    test(`${path}: ${name}Hex equals --pl-${name} in src/ui/tokens.css.js`, () => {
      assert.equal(swiftHex(path, name), cssHex(name));
    });
  }
}

test('the brand is still paper #F5F0E6 and ink #1A1F2E (design D3)', () => {
  assert.equal(cssHex('paper'), 'F5F0E6');
  assert.equal(cssHex('ink'), '1A1F2E');
});
