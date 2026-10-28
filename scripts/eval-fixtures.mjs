// Usage:
//   ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)" \
//   ANTHROPIC_WORKSPACE_ID="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/anthropic/configs/default.json")))["workspace_id"])')" \
//   node scripts/eval-fixtures.mjs [--hard]
import { readFileSync } from 'node:fs';
import { callJson } from '../src/lib/api.js';
import { buildIncomingRequest, buildOutgoingRequest, parseIncoming, parseOutgoing } from '../src/lib/prompts.js';

const key = process.env.ANTHROPIC_API_KEY;
const workspace = process.env.ANTHROPIC_WORKSPACE_ID;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }

const transport = async (body) => {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      ...(workspace ? { 'anthropic-workspace-id': workspace } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, retry_after: res.headers.get('retry-after'), body: await res.json().catch(() => ({})) };
};

const hard = process.argv.includes('--hard');
const cases = JSON.parse(readFileSync(new URL('./fixtures/conversations.json', import.meta.url)));
let failures = 0;

for (const c of cases) {
  console.log(`\n=== ${c.name}`);
  const t0 = Date.now();
  const inc = await callJson(buildIncomingRequest({
    model: 'claude-sonnet-5-5', memo: c.memo, context: c.context, otherTarget: c.otherTarget,
    items: c.items.map(({ id, text }) => ({ id, text })),
  }), parseIncoming, { transport });
  console.log(`incoming ${Date.now() - t0}ms`);
  for (const it of c.items) {
    const r = inc[it.id];
    const ok = r && r.src_lang === it.expect_src;
    if (!ok) failures++;
    console.log(`  [${ok ? 'ok' : 'FAIL'}] ${it.text}\n      -> (${r?.src_lang}) ${r?.translation}`);
  }
  const t1 = Date.now();
  const out = await callJson(buildOutgoingRequest({
    model: hard ? 'claude-opus-5-5' : 'claude-sonnet-5-5', profile: hard ? 'hard' : 'outgoing',
    memo: c.memo, context: c.context, korean: c.outgoing.korean, lang: c.outgoing.lang,
  }), parseOutgoing, { transport });
  console.log(`outgoing ${Date.now() - t1}ms\n  ${c.outgoing.korean}\n  -> ${out.translation}\n  <- ${out.back_translation}`);
}
console.log(`\n${failures} src_lang failure(s)`);
process.exit(failures ? 1 : 0);
