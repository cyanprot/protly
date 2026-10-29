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

test('the live eval wraps the note in the same about_writer tags as the keyboard', () => {
  assert.equal(value(core, 'openTag'), '"<about_writer>"');
  assert.equal(value(core, 'closeTag'), '"</about_writer>"');
  assert.match(core, /header \+ "\\n" \+ openTag \+ "\\n" \+ note \+ "\\n" \+ closeTag/);
  assert.ok(
    read('scripts/eval-polish.mjs').includes('`${KEYBOARD_PROMPT}\\n${ABOUT_HEADER}\\n<about_writer>\\n${note}\\n</about_writer>`'),
    'eval-polish.mjs builds the keyboard system prompt as AboutMe.system does',
  );
});

test('the container app counts and cuts the note by unicode scalars, as AboutMe does', () => {
  assert.doesNotMatch(app, /aboutMe\.count|new\.count|new\.prefix\(/);
  assert.match(app, /aboutMe\.unicodeScalars\.count/);
  assert.match(app, /new\.unicodeScalars\.count > AboutMeLink\.cap/);
  assert.match(app, /new\.unicodeScalars\.prefix\(AboutMeLink\.cap\)/);
});
