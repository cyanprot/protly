import { hasHangul } from './lang.js';

export const initial = () => ({ mode: 'idle', korean: null, profile: null, lang: null, shown: null, reqId: 0 });

const norm = (t) => (t ?? '').replace(/\s+/g, ' ').trim();

function translate(s, korean, profile, lang) {
  const reqId = s.reqId + 1;
  return {
    state: { mode: 'translating', korean, profile, lang, shown: null, reqId },
    effect: { type: 'translate', reqId, korean, profile, lang },
  };
}

const idle = (s) => ({ ...s, mode: 'idle', korean: null, profile: null, lang: null, shown: null });

export function reduce(s, e) {
  switch (e.type) {
    case 'enter': {
      const profile = e.hard ? 'hard' : 'outgoing';
      if (s.mode === 'translating') return { state: s, effect: { type: 'block' } };
      if (s.mode === 'preview') {
        // New draft: Hangul that is not the shown translation (which may keep ㅋㅋ or a Korean name).
        if (hasHangul(e.text) && s.lang !== 'ko' && norm(e.text) !== norm(s.shown)) return translate(s, e.text, profile, null);
        if (e.hard) return translate(s, s.korean, 'hard', s.lang);
        return { state: idle(s), effect: { type: 'sent', korean: s.korean } };
      }
      if (!hasHangul(e.text)) return { state: s, effect: { type: 'pass' } };
      return translate(s, e.text, profile, null);
    }
    case 'result':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return {
        state: { ...s, mode: 'preview', lang: e.lang, shown: e.translation },
        effect: {
          type: 'show', translation: e.translation, back_translation: e.back_translation,
          profile: s.profile, lang: e.lang, model: e.model,
        },
      };
    case 'fail':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return { state: idle(s), effect: { type: 'fail', message: e.message, korean: s.korean } };
    case 'lang':
      if (s.mode !== 'preview') return { state: s, effect: { type: 'none' } };
      return translate(s, s.korean, s.profile, e.lang);
    case 'esc':
      if (s.mode === 'preview' || s.mode === 'translating') {
        return { state: idle(s), effect: { type: 'restore', korean: s.korean } };
      }
      return { state: s, effect: { type: 'pass' } };
    case 'reset':
      return { state: idle(s), effect: { type: 'none' } };
    default:
      return { state: s, effect: { type: 'none' } };
  }
}
