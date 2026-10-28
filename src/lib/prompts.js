import { ApiError } from './api.js';
import { langName } from './lang.js';

// useFormat: the Task 2 spike confirmed format works with adaptive thinking; false is only a fallback switch.
export const PROFILES = {
  incoming: { thinkingOff: true, effort: 'low', max_tokens: 8192, useFormat: true },
  outgoing: { thinkingOff: false, effort: 'medium', max_tokens: 16000, useFormat: true },
  hard: { thinkingOff: false, effort: 'high', max_tokens: 32000, useFormat: true },
  memo: { thinkingOff: false, effort: 'medium', max_tokens: 16000, useFormat: true },
};

export function thinkingFor(model, off) {
  return off && model.startsWith('claude-sonnet') ? { type: 'between_tools' } : { type: 'adaptive' };
}

const INCOMING_SYSTEM = `You translate Instagram direct messages between friends for a Korean speaker.
For every listed message:
- Detect its language and report it as an ISO 639-1 code in src_lang ("en", "ru", "ko", ...).
- Korean: return the original text unchanged.
- English: translate into Korean.
- Any other language: translate into the language given as TARGET_FOR_OTHER.
Style:
- Keep the register. Casual stays casual. Korean output uses casual speech (banmal) unless the memo says otherwise.
- Render slang and internet speak as natural equivalents, not literal glosses.
- Keep emoji, names, @handles, URLs and line breaks as they are.
- Use the recent conversation and the thread memo to resolve pronouns, jokes and references.
- Translate only the listed messages, never the context.
Return one item per listed message with the same id.`;

const OUTGOING_SYSTEM = `You help a Korean speaker write Instagram direct messages to a friend.
Translate the Korean draft into the TARGET language so it reads like a native speaker texting a friend.
- Korean often drops the subject. Use the recent conversation and the memo to decide who does what to whom.
- Match the register and tone of the conversation. Casual stays casual. Keep emoji.
- Do not add content, greetings, sign-offs or explanations that are not in the draft.
- back_translation: translate your output back into natural Korean, close enough that the writer can check the meaning.`;

const MEMO_SYSTEM = `Read this Instagram DM conversation and write a short memo, at most 5 lines in English, that helps a translator.
Cover: who the friend is to the user, the tone and register both sides use, nicknames, running jokes or recurring topics.
Only state what the conversation supports.`;

const INCOMING_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, src_lang: { type: 'string' }, translation: { type: 'string' } },
        required: ['id', 'src_lang', 'translation'],
        additionalProperties: false,
      },
    },
  },
  required: ['items'],
  additionalProperties: false,
};

const OUTGOING_SCHEMA = {
  type: 'object',
  properties: { translation: { type: 'string' }, back_translation: { type: 'string' } },
  required: ['translation', 'back_translation'],
  additionalProperties: false,
};

const MEMO_SCHEMA = {
  type: 'object',
  properties: { memo: { type: 'string' } },
  required: ['memo'],
  additionalProperties: false,
};

const formatContext = (context) =>
  context.map((m) => `${m.from === 'me' ? 'ME' : 'FRIEND'}: ${m.text}`).join('\n') || '(none)';

function request(model, profileName, system, userText, schema) {
  const p = PROFILES[profileName];
  const output_config = { effort: p.effort };
  let content = userText;
  if (p.useFormat) output_config.format = { type: 'json_schema', schema };
  else content += `\n\nReply with only a JSON object matching this schema:\n${JSON.stringify(schema)}`;
  return {
    model,
    max_tokens: p.max_tokens,
    thinking: thinkingFor(model, p.thinkingOff),
    output_config,
    system,
    messages: [{ role: 'user', content }],
  };
}

export function buildIncomingRequest({ model, memo, context, items, otherTarget }) {
  const text = [
    `TARGET_FOR_OTHER: ${langName(otherTarget)}`,
    `THREAD MEMO:\n${memo || '(none)'}`,
    `RECENT CONVERSATION (oldest first):\n${formatContext(context)}`,
    `MESSAGES TO TRANSLATE:\n${JSON.stringify(items.map(({ id, text }) => ({ id, text })))}`,
  ].join('\n\n');
  return request(model, 'incoming', INCOMING_SYSTEM, text, INCOMING_SCHEMA);
}

export function buildOutgoingRequest({ model, profile, memo, context, korean, lang }) {
  const text = [
    `TARGET: ${langName(lang)}`,
    `THREAD MEMO:\n${memo || '(none)'}`,
    `RECENT CONVERSATION (oldest first):\n${formatContext(context)}`,
    `KOREAN DRAFT:\n${korean}`,
  ].join('\n\n');
  return request(model, profile, OUTGOING_SYSTEM, text, OUTGOING_SCHEMA);
}

export function buildMemoRequest({ model, context }) {
  return request(model, 'memo', MEMO_SYSTEM, `CONVERSATION (oldest first):\n${formatContext(context)}`, MEMO_SCHEMA);
}

function extractJson(resp) {
  if (resp.stop_reason === 'refusal') throw new ApiError('refused', 'Model refused');
  if (resp.stop_reason === 'max_tokens') throw new ApiError('parse', 'Output truncated');
  const text = (resp.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
  try {
    return JSON.parse(text);
  } catch {
    const m = text.match(/\{[\s\S]*\}/);
    if (m) { try { return JSON.parse(m[0]); } catch {} }
    throw new ApiError('parse', 'Response is not JSON');
  }
}

export function parseIncoming(resp) {
  const j = extractJson(resp);
  if (!Array.isArray(j.items)) throw new ApiError('parse', 'items missing');
  const out = {};
  for (const it of j.items) {
    if (typeof it.id !== 'string' || typeof it.translation !== 'string') throw new ApiError('parse', 'bad item');
    out[it.id] = { src_lang: it.src_lang, translation: it.translation };
  }
  return out;
}

export function parseOutgoing(resp) {
  const j = extractJson(resp);
  if (typeof j.translation !== 'string' || typeof j.back_translation !== 'string') {
    throw new ApiError('parse', 'translation fields missing');
  }
  return { translation: j.translation, back_translation: j.back_translation };
}

export function parseMemo(resp) {
  const j = extractJson(resp);
  if (typeof j.memo !== 'string') throw new ApiError('parse', 'memo missing');
  return j.memo;
}
