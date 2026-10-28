import { hasHangul, parseLangPrefix } from './lang.js';

// korean: the source text. The Korean draft (prefix included, so Esc restores it), or the English draft being polished.
// kind: 'translate' | 'polish'.
export const initial = () => ({ mode: 'idle', kind: null, korean: null, profile: null, lang: null, shown: null, reqId: 0 });

const norm = (t) => (t ?? '').replace(/\s+/g, ' ').trim();

// lang: an explicit choice (chip or a re-run), else the draft's prefix, else null (the thread decides).
function translate(s, korean, profile, lang) {
  const reqId = s.reqId + 1;
  const p = parseLangPrefix(korean);
  return {
    state: { mode: 'translating', kind: 'translate', korean, profile, lang, shown: null, reqId },
    effect: { type: 'translate', kind: 'translate', reqId, korean: p.text, profile, lang: lang ?? p.lang },
  };
}

function polish(s, text, profile) {
  const reqId = s.reqId + 1;
  return {
    state: { mode: 'translating', kind: 'polish', korean: text, profile, lang: null, shown: null, reqId },
    effect: { type: 'translate', kind: 'polish', reqId, korean: text, profile, lang: null },
  };
}

const idle = (s) => ({ ...s, mode: 'idle', kind: null, korean: null, profile: null, lang: null, shown: null });

export function reduce(s, e) {
  switch (e.type) {
    case 'enter': {
      const profile = e.hard ? 'hard' : 'outgoing';
      if (s.mode === 'translating') return { state: s, effect: { type: 'block' } };
      if (s.mode === 'preview') {
        // New draft: Hangul that is not the shown translation (which may keep ㅋㅋ or a Korean name).
        if (hasHangul(e.text) && s.lang !== 'ko' && norm(e.text) !== norm(s.shown)) return translate(s, e.text, profile, null);
        if (e.hard) return s.kind === 'polish' ? polish(s, s.korean, 'hard') : translate(s, s.korean, 'hard', s.lang);
        // Anything else is sent as is, an edit included: polish starts only from idle.
        return { state: idle(s), effect: { type: 'sent', korean: s.korean } };
      }
      if (hasHangul(e.text)) return translate(s, e.text, profile, null);
      if (e.polish && /\p{L}/u.test(e.text)) return polish(s, e.text, profile);
      return { state: s, effect: { type: 'pass' } };
    }
    // Alt+T in the composer: translate or polish without sending. Explicit, so polish needs no toggle.
    case 'run': {
      if (s.mode !== 'idle') return { state: s, effect: { type: 'none' } };
      if (hasHangul(e.text)) return translate(s, e.text, 'outgoing', null);
      if (/\p{L}/u.test(e.text)) return polish(s, e.text, 'outgoing');
      return { state: s, effect: { type: 'none' } };
    }
    case 'result':
      if (s.mode !== 'translating' || e.reqId !== s.reqId) return { state: s, effect: { type: 'none' } };
      return {
        state: { ...s, mode: 'preview', lang: s.kind === 'polish' ? null : e.lang, shown: e.translation },
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
