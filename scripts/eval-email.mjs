// Usage:
//   ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/api-key)" \
//   ANTHROPIC_WORKSPACE_ID="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.config/anthropic/configs/default.json")))["workspace_id"])')" \
//   node scripts/eval-email.mjs
import { callJson } from '../src/lib/api.js';
import { buildEmailRequest, parseEmail } from '../src/lib/prompts.js';

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

// Synthetic threads only.
const cases = [
  {
    name: 'formal English reply', expect: 'en',
    context: [{ from: 'them', text: 'Dear Mr. Kim,\n\nCould you confirm whether the documents can be submitted by Friday?\n\nBest regards,\nProf. Allen' }],
    korean: '안녕하세요 교수님,\n\n금요일까지 제출 가능합니다. 혹시 추가로 필요한 서류가 있으면 알려주세요.\n\n감사합니다.',
  },
  {
    name: 'casual Russian reply', expect: 'ru',
    context: [{ from: 'them', text: 'Привет! Ну что, в субботу встречаемся? Напиши, во сколько удобно.' }],
    korean: '응 좋아! 3시쯤 어때? 늦으면 연락할게',
  },
  {
    name: 'new email, no thread', expect: 'en',
    context: [],
    korean: '안녕하세요, 다음 주 미팅 일정을 조율하고 싶습니다. 화요일이나 수요일 오후 중 편하신 시간을 알려주세요.',
  },
];

let failures = 0;
for (const c of cases) {
  const t0 = Date.now();
  const r = await callJson(buildEmailRequest({ model: 'claude-sonnet-5-5', context: c.context, korean: c.korean }), parseEmail, { transport });
  const ok = r.lang === c.expect;
  if (!ok) failures++;
  console.log(`\n=== ${c.name} [${ok ? 'ok' : 'FAIL'}] ${r.lang} ${Date.now() - t0}ms\n${r.translation}\n<- ${r.back_translation}`);
}
console.log(`\n${failures} lang failure(s)`);
process.exit(failures ? 1 : 0);
