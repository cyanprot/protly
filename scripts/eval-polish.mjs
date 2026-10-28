// Live API check of the polish prompt and the outgoing prompt fixes, with the real builders and parsers.
// Usage:
//   ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)" \
//   ANTHROPIC_WORKSPACE_ID="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/anthropic/configs/default.json")))["workspace_id"])')" \
//   node scripts/eval-polish.mjs
import { callJson } from '../src/lib/api.js';
import { buildPolishRequest, buildOutgoingRequest, parseOutgoing } from '../src/lib/prompts.js';

const key = process.env.ANTHROPIC_API_KEY;
const workspace = process.env.ANTHROPIC_WORKSPACE_ID;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }

let usage = null;
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
  const j = await res.json().catch(() => ({}));
  usage = j.usage;
  return { status: res.status, retry_after: res.headers.get('retry-after'), body: j };
};

const MODEL = 'claude-sonnet-5-5';
const HANGUL = /[가-힣]/;
const NO_PUNCT = (t) => !/[—–;/]/.test(t);
const paragraphs = (t) => t.trim().split(/\n\s*\n/).length;
const MEMO = 'Mira Volkova: female classmate, Russian-speaking. Jokey, casual.';
const EMAIL = 'Hi Prof. Allen,\n\ni wanted to ask if its possible to submit the lab report on monday instead of friday, '
  + 'because i had a really bad cold this week; i can send a doctors note if needed.\n\n'
  + 'Additionally the centrifuge in room 204 is broken / leaking, maybe someone should look at it.\n\nThanks,\nCyan';

const polish = (draft) => buildPolishRequest({ model: MODEL, draft });
const out = (korean, lang, memo = '') =>
  buildOutgoingRequest({ model: MODEL, profile: 'outgoing', memo, context: [], korean, lang });

const CASES = [
  {
    name: 'polish chat, typos',
    body: polish('i dont know what your saying but its very good idea, lets do it tommorow'),
    check: (r) => !HANGUL.test(r.translation) && /tomorrow/i.test(r.translation) && HANGUL.test(r.back_translation),
  },
  {
    name: 'polish chat, CyanStyle rules',
    body: polish('Additionally i think its a really nice color — lets meet at the center tomorrow; ok?'),
    check: (r) => NO_PUNCT(r.translation) && /colour/i.test(r.translation) && /centre/i.test(r.translation) && !/additionally/i.test(r.translation),
  },
  {
    name: 'polish email, greeting and paragraphs kept',
    body: polish(EMAIL),
    check: (r) => /^Hi Prof\. Allen,/.test(r.translation.trim()) && /Thanks,\s*\nCyan\s*$/.test(r.translation)
      && paragraphs(r.translation) === paragraphs(EMAIL) && NO_PUNCT(r.translation) && !/additionally/i.test(r.translation),
  },
  ...[1, 2, 3].map((n) => ({
    name: `out, female friend in Russian (run ${n})`,
    body: out('노트 고마워 너 덕분에 살았다', 'ru', MEMO),
    check: (r) => /спасла/i.test(r.translation) && !/(?<![а-яё])спас(?![а-яё])/i.test(r.translation),
  })),
  {
    name: 'out, never Korean',
    body: out('ㅋㅋ 진짜?', 'en'),
    check: (r) => !HANGUL.test(r.translation.replace(/ㅋ/g, '')) && r.translation.trim().length > 0,
  },
];

let failed = 0;
for (const c of CASES) {
  const t0 = Date.now();
  let r;
  try {
    r = await callJson(c.body, parseOutgoing, { transport });
  } catch (e) {
    failed++;
    console.log(`FAIL ${c.name}: ${e.kind} ${e.message}`);
    continue;
  }
  const ok = c.check(r);
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${c.name}  ${Date.now() - t0} ms  in=${usage?.input_tokens} out=${usage?.output_tokens}`);
  console.log(`  translation: ${r.translation.replace(/\n/g, ' / ')}`);
  console.log(`  back: ${r.back_translation.replace(/\n/g, ' / ')}`);
}
console.log(`\n${failed} failure(s) of ${CASES.length}`);
process.exit(failed ? 1 : 0);
