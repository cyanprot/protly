const HANGUL = /[ᄀ-ᇿ㄰-㆏가-힯]/;
const HANGUL_G = /[ᄀ-ᇿ㄰-㆏가-힯]/g;

export function hasHangul(s) {
  return HANGUL.test(s);
}

// Hangul present and no letters from any other script.
export function isKoreanOnly(s) {
  return hasHangul(s) && !/\p{L}/u.test(s.replace(HANGUL_G, ''));
}

// Target language for an incoming message, or null if it stays as is.
// otherTarget is the per-thread toggle for non-English languages: 'ko' | 'en'.
export function incomingTarget(srcLang, otherTarget) {
  if (srcLang === 'ko') return null;
  if (srcLang === 'en') return 'ko';
  return otherTarget;
}

export function resolveOutputLang(thread) {
  if (thread.outputLang && thread.outputLang !== 'auto') return thread.outputLang;
  if (thread.partnerLang && thread.partnerLang !== 'ko') return thread.partnerLang;
  return 'en';
}

// results: oldest first, each { from: 'me' | 'partner', src_lang }.
export function latestPartnerLang(results) {
  for (let i = results.length - 1; i >= 0; i--) {
    const r = results[i];
    if (r.from === 'partner' && r.src_lang && r.src_lang !== 'ko') return r.src_lang;
  }
  return null;
}

// Picker order: the common ones first, then the rest by name. Codes are ISO 639-1
// (yue has none, so it uses 639-3); the model can still write any language not listed.
export const LANG_NAMES = {
  ko: 'Korean', en: 'English', ru: 'Russian', es: 'Spanish', ja: 'Japanese',
  zh: 'Chinese', fr: 'French', de: 'German', uk: 'Ukrainian', pt: 'Portuguese',
  ar: 'Arabic', be: 'Belarusian', bn: 'Bengali', bg: 'Bulgarian', yue: 'Cantonese',
  hr: 'Croatian', cs: 'Czech', da: 'Danish', nl: 'Dutch', et: 'Estonian',
  fi: 'Finnish', ka: 'Georgian', el: 'Greek', he: 'Hebrew', hi: 'Hindi',
  hu: 'Hungarian', id: 'Indonesian', it: 'Italian', kk: 'Kazakh', lv: 'Latvian',
  lt: 'Lithuanian', ms: 'Malay', mn: 'Mongolian', no: 'Norwegian', fa: 'Persian',
  pl: 'Polish', pa: 'Punjabi', ro: 'Romanian', sr: 'Serbian', sk: 'Slovak',
  sv: 'Swedish', tl: 'Tagalog', th: 'Thai', tr: 'Turkish', ur: 'Urdu',
  uz: 'Uzbek', vi: 'Vietnamese',
};

export const langName = (code) => LANG_NAMES[code] || code;

// "ru: 안녕" -> { lang: 'ru', text: '안녕' }. Only known non-Korean codes count, so "ok:" stays text.
// Callers apply it to Korean drafts only, which keeps English such as "no: ..." (Norwegian) out of it.
export function parseLangPrefix(s) {
  const m = s.match(/^\s*([a-z]{2,3}):\s*/i);
  const code = m?.[1].toLowerCase();
  if (!code || code === 'ko' || !(code in LANG_NAMES)) return { lang: null, text: s };
  return { lang: code, text: s.slice(m[0].length) };
}
