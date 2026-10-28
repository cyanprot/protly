// Sends ios/body-template.json to the live API the way the iOS Shortcut does, using a synthetic DM screenshot.
// Usage: node scripts/eval-ios.mjs <dm.jpg> [web.jpg group.jpg]   (key read from ~/.config/anthropic/api-key, never printed)
// The jpgs are 720 px renders of scripts/fixtures/ios-dm.html, ios-web.html and ios-group.html.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const key = readFileSync(`${homedir()}/.config/anthropic/api-key`, 'utf8').trim();
// The laptop key is org-level and needs a workspace header; the phone key is made inside a workspace and does not.
let workspace = null;
try { workspace = JSON.parse(readFileSync(`${homedir()}/.config/anthropic/configs/default.json`, 'utf8')).workspace_id; } catch {}
const template = readFileSync(new URL('../ios/body-template.json', import.meta.url), 'utf8');
const img = (i) => (process.argv[i] ? readFileSync(process.argv[i]).toString('base64') : null);
const [DM, WEB, GROUP] = [img(2), img(3), img(4)];
const MEMO = 'Mira Volkova (mira.vlk): female classmate, Russian-speaking. Reply in Russian. Jokey, casual.';
const DRAFT = 'ㅇㅋ 3시에 봐\n노트 고마워 "진짜" 살았다 ㅋㅋ \\ C:\\new\t$1 😂';

// Same slot filling as the shortcut: escape the text for a JSON string, then plain replace (no regex).
const fill = (text, image) => template
  .replace('{{IMAGE_B64}}', () => image)
  .replace('{{TEXT}}', () => JSON.stringify(text).slice(1, -1));
const textFor = (mode, memo, draft) =>
  `PEOPLE:\n${memo || '(none)'}\n\nMODE: ${mode}` + (mode !== 'in' ? `\n\nDRAFT:\n${draft}` : '');

const CASES = [
  { name: 'in, memo', text: textFor('in', MEMO), check: (r) => /[가-힣]/.test(r.translation) },
  { name: 'out, memo says Russian', text: textFor('out', MEMO, DRAFT), check: (r) => /[а-яё]/i.test(r.translation) && /[가-힣]/.test(r.back_translation) },
  { name: 'out, ja: prefix beats memo', text: textFor('out', MEMO, 'ja: ' + DRAFT), check: (r) => /[\u3040-\u30ff]/.test(r.translation) && !/^ja:/i.test(r.translation) && !/^ja:/i.test(r.back_translation) },
  { name: 'fix, English draft', text: textFor('fix', MEMO, 'i dont know what your saying but its very good idea, lets do it tommorow'), check: (r) => !/[가-힣]/.test(r.translation) && /tomorrow/i.test(r.translation) && /[가-힣]/.test(r.back_translation) },
  { name: 'fix, CyanStyle rules', text: textFor('fix', MEMO, 'Additionally i think its a really nice color \u2014 lets meet at the center tomorrow; ok?'), check: (r) => !/[\u2014\u2013;\/]/.test(r.translation) && /colour/i.test(r.translation) && /centre/i.test(r.translation) && !/additionally/i.test(r.translation) },
  { name: 'out, no memo', text: textFor('out', '', DRAFT), check: (r) => r.translation.length > 0 && !/[가-힣]/.test(r.translation) },
  { name: 'in, web page (Spanish)', image: WEB, text: textFor('in', MEMO), check: (r) => /[가-힣]/.test(r.translation) && /야시장|마켓|시장/.test(r.translation) && !/로그인|구독|광고/.test(r.translation) },
  { name: 'in, group chat with Me:', image: GROUP, text: textFor('in', 'Me: cyan\n' + MEMO), check: (r) => /[가-힣]/.test(r.translation) && r.translation.trim().split('\n').length === 2 && /Diego/.test(r.translation) && /Hana/.test(r.translation) && !/라멘/.test(r.translation) },
];

let failed = 0;
for (const c of CASES.map((c) => ({ image: DM, ...c })).filter((c) => c.image)) {
  const t0 = Date.now();
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json', ...(workspace ? { 'anthropic-workspace-id': workspace } : {}) },
    body: fill(c.text, c.image),
  });
  const j = await res.json();
  const ms = Date.now() - t0;
  if (j.type === 'error') { failed++; console.log(`FAIL ${c.name}: ${j.error.message}`); continue; }
  // Same parse as the shortcut: last content block, its text, as JSON.
  const r = JSON.parse(j.content.at(-1).text);
  const ok = j.stop_reason === 'end_turn' && c.check(r);
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${c.name}  ${ms} ms  in=${j.usage.input_tokens} out=${j.usage.output_tokens}  blocks=${j.content.map((b) => b.type).join(',')}`);
  console.log(`  translation: ${r.translation.replace(/\n/g, ' / ')}`);
  if (r.back_translation) console.log(`  back: ${r.back_translation.replace(/\n/g, ' / ')}`);
}
process.exit(failed ? 1 : 0);
