// Usage: ANTHROPIC_API_KEY=... node scripts/spike-api.mjs
const key = process.env.ANTHROPIC_API_KEY;
if (!key) { console.error('ANTHROPIC_API_KEY not set'); process.exit(1); }

const schema = {
  type: 'object',
  properties: { translation: { type: 'string' }, back_translation: { type: 'string' } },
  required: ['translation', 'back_translation'],
  additionalProperties: false,
};
const user = 'Translate to English, casual texting style: "야 어제 거기 진짜 미쳤더라 ㅋㅋ 다음에 또 가자"';

const variants = {
  'sonnet between_tools low + format': { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools' }, effort: 'low', max_tokens: 4096, format: true },
  'sonnet adaptive medium + format':   { model: 'claude-sonnet-5-5', thinking: { type: 'adaptive' }, effort: 'medium', max_tokens: 16000, format: true },
  'opus adaptive high + format':       { model: 'claude-opus-5-5', thinking: { type: 'adaptive' }, effort: 'high', max_tokens: 32000, format: true },
  'opus between_tools low':            { model: 'claude-opus-5-5', thinking: { type: 'between_tools' }, effort: 'low', max_tokens: 4096, format: true },
  'sonnet adaptive medium, no format': { model: 'claude-sonnet-5-5', thinking: { type: 'adaptive' }, effort: 'medium', max_tokens: 16000, format: false },
};

async function run(name, v, extraHeaders = {}) {
  const body = {
    model: v.model,
    max_tokens: v.max_tokens,
    thinking: v.thinking,
    output_config: { effort: v.effort, ...(v.format ? { format: { type: 'json_schema', schema } } : {}) },
    messages: [{ role: 'user', content: v.format ? user : user + '\nReply as JSON {"translation":..., "back_translation":...}' }],
  };
  const t0 = Date.now();
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      ...(process.env.ANTHROPIC_WORKSPACE_ID ? { 'anthropic-workspace-id': process.env.ANTHROPIC_WORKSPACE_ID } : {}),
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  const ms = Date.now() - t0;
  const text = (json.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
  const types = (json.content || []).map(b => b.type).join(',');
  console.log(`\n== ${name}  [${res.status}] ${ms}ms  blocks=${types}  stop=${json.stop_reason}`);
  console.log(res.ok ? text : JSON.stringify(json.error));
}

for (const [name, v] of Object.entries(variants)) await run(name, v);

// Simulate an extension-origin request.
const sv = variants['sonnet between_tools low + format'];
await run('origin chrome-extension, WITHOUT browser header', sv, { origin: 'chrome-extension://abcdefghijklmnop' });
await run('origin chrome-extension, WITH browser header', sv, {
  origin: 'chrome-extension://abcdefghijklmnop',
  'anthropic-dangerous-direct-browser-access': 'true',
});
