import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), 'utf8');
const core = read('ios-app/ProtlyCore/Sources/ProtlyCore/AboutMe.swift');
const app = read('ios-app/Sources/Protly/ProtlyApp.swift');
const value = (src, name) => src.match(new RegExp(`static let ${name} = ("[^"]*"|\\d+)`))?.[1];

test('the container app repeats the AboutMe constants exactly (marker, cap, defaults key)', () => {
  for (const name of ['marker', 'cap', 'defaultsKey']) {
    assert.ok(value(core, name), `${name} in AboutMe.swift`);
    assert.equal(value(app, name), value(core, name), name);
  }
});

test('the live eval sends the same note header as the keyboard (scripts/eval-polish.mjs)', () => {
  const header = value(core, 'header');
  assert.ok(header, 'header in AboutMe.swift');
  const evalHeader = read('scripts/eval-polish.mjs').match(/const ABOUT_HEADER = '([^']*)'/)?.[1];
  assert.equal(`"${evalHeader}"`, header);
});
