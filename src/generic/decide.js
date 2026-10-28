import { hasHangul, isKoreanOnly, parseLangPrefix } from '../lib/lang.js';

const LETTER = /\p{L}/u;

// What Alt+T does with a text box. A prefix wins whatever the script (design section 6); this is the one place a
// prefix applies to non-Korean text, so "no: ..." in an English box becomes Norwegian. Intended.
export function decideBox(text) {
  const p = parseLangPrefix(text);
  if (p.lang) return p.text.trim() ? { kind: 'translate', lang: p.lang, text: p.text } : { kind: 'none' };
  if (hasHangul(text)) return { kind: 'translate', lang: 'en', text };
  if (LETTER.test(text)) return { kind: 'polish', text };
  return { kind: 'none' };
}

// A selection outside any box goes to Korean.
export function decideSelection(text) {
  const t = (text ?? '').trim();
  if (!t) return 'none';
  if (isKoreanOnly(t)) return 'already-ko';
  return LETTER.test(t) ? 'translate' : 'none';
}
