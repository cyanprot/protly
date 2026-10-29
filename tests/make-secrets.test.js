// ios-app/scripts/make-secrets.sh, run offline against a copy in a temp git repo with a fake HOME and a fake key.
// The real HOME, the real key and the real Secrets.swift are never touched.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SCRIPT = new URL('../ios-app/scripts/make-secrets.sh', import.meta.url);
const FAKE_KEY = 'sk-ant-test-FAKE_key-0123456789';
const OUT = 'ios-app/Sources/ProtlyKeyboard/Secrets.swift';

function sandbox(t, { ignored = true, keyMode = 0o600, keyVia = 'file' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'protly-secrets-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const repo = join(root, 'repo');
  const env = {
    PATH: process.env.PATH, HOME: home, LANG: 'C',
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CEILING_DIRECTORIES: root,
  };
  mkdirSync(join(home, '.config', 'protly'), { recursive: true });
  const keyFile = join(home, '.config', 'protly', 'phone-api-key');
  const target = keyVia === 'symlink' ? join(home, 'elsewhere-key') : keyFile;
  writeFileSync(target, `${FAKE_KEY}\n`);
  chmodSync(target, keyMode);
  if (keyVia === 'symlink') symlinkSync(target, keyFile);

  mkdirSync(join(repo, 'ios-app', 'scripts'), { recursive: true });
  mkdirSync(join(repo, 'ios-app', 'Sources', 'ProtlyKeyboard'), { recursive: true });
  copyFileSync(SCRIPT, join(repo, 'ios-app', 'scripts', 'make-secrets.sh'));
  writeFileSync(join(repo, '.gitignore'), ignored ? `${OUT}\n` : 'node_modules/\n');
  const init = spawnSync('git', ['init', '-q', repo], { env, encoding: 'utf8' });
  assert.equal(init.status, 0, init.stderr);

  const run = () => {
    const r = spawnSync('bash', [join(repo, 'ios-app', 'scripts', 'make-secrets.sh')], { env, cwd: root, encoding: 'utf8' });
    assert.ok(!`${r.stdout}${r.stderr}`.includes(FAKE_KEY), 'the key never reaches the output');
    return r;
  };
  return { out: join(repo, OUT), run };
}

const hasTools = ['bash', 'git'].every((c) => spawnSync(c, ['--version']).status === 0);

test('make-secrets: refuses, and writes nothing, when Secrets.swift is not gitignored', { skip: !hasTools }, (t) => {
  const s = sandbox(t, { ignored: false });
  const r = s.run();
  assert.equal(r.status, 1);
  assert.match(r.stderr, /not gitignored; refusing/);
  assert.equal(existsSync(s.out), false);
});

test('make-secrets: writes Secrets.swift with mode 600 and the key in the literal, quietly', { skip: !hasTools }, (t) => {
  const s = sandbox(t);
  writeFileSync(s.out, 'stale'); // an older, wider file is replaced, not reused
  chmodSync(s.out, 0o644);
  const r = s.run();
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, ''); // a 600 key file draws no warning
  assert.match(r.stdout, /^wrote Sources\/ProtlyKeyboard\/Secrets\.swift$/m);
  assert.equal(statSync(s.out).mode & 0o777, 0o600);
  assert.match(readFileSync(s.out, 'utf8'), new RegExp(`static let apiKey = "${FAKE_KEY}"`));
});

// Same rule as the host's key_shared: any group or other bit (mode & 0o077) is too open, not only the read bits.
test('make-secrets: warns on a key file with any group or other bit, through a symlink too', { skip: !hasTools }, (t) => {
  for (const [keyMode, keyVia] of [[0o644, 'file'], [0o640, 'file'], [0o604, 'file'], [0o620, 'file'], [0o602, 'file'],
    [0o610, 'file'], [0o601, 'file'], [0o644, 'symlink'], [0o620, 'symlink']]) {
    const s = sandbox(t, { keyMode, keyVia });
    const r = s.run();
    const what = `${keyMode.toString(8)} ${keyVia}`;
    assert.equal(r.status, 0, what);
    assert.match(r.stderr, /warning: .*phone-api-key is open to group or others; chmod 600 it/, what);
    assert.equal(statSync(s.out).mode & 0o777, 0o600, what);
  }
});

test('make-secrets: owner-only key file modes draw no warning', { skip: !hasTools }, (t) => {
  for (const keyMode of [0o600, 0o400, 0o700]) {
    const s = sandbox(t, { keyMode });
    const r = s.run();
    assert.equal(r.status, 0, keyMode.toString(8));
    assert.equal(r.stderr, '', keyMode.toString(8));
  }
});
