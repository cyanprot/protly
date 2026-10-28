import { initial, reduce } from '../lib/preview.js';
import { hasHangul, langName, LANG_NAMES } from '../lib/lang.js';
import { findComposer, getComposerText, setComposerText } from './dom.js';
import { ask, getCurrent, contextFor, showBanner, bannerFor } from './main.js';

const COMPOSE_ENTER_MS = 300; // a deferred IME Enter must be followed by compositionend within this window
const WRITE_SETTLE_MS = 50;   // editors such as Lexical commit DOM updates asynchronously
const norm = (s) => s.replace(/\s+/g, ' ').trim();
const isEnter = (e) => e.key === 'Enter' || e.code === 'Enter' || e.code === 'NumpadEnter';
const modelLabel = (m) => (m && m.includes('opus') ? 'Opus' : 'Sonnet');
const block = (e) => { e.preventDefault(); e.stopImmediatePropagation(); };

export function mountOutgoing(cur) {
  let state = initial();
  let note = null;
  let enterAfterComposition = null; // { hard, at }
  let lastText = ''; // composer text while previewing; recorded if Instagram's Send button sends it
  let writing = false; // our own composer writes fire input events; ignore them

  const composer = () => findComposer(document);
  const text = (s) => document.createTextNode(s);
  const write = async (c, s) => { writing = true; try { await setComposerText(c, s); } finally { writing = false; } };

  // Composer selector check (design: selector miss = inactive + badge).
  setTimeout(() => {
    if (getCurrent() === cur && !composer()) {
      ask({ type: 'badge', text: '!' }).catch(() => {});
      console.warn('[igt] composer not found; outgoing translation inactive');
    }
  }, 3000);

  const showNote = (nodes, isError) => {
    const c = composer();
    if (!c) return;
    if (!note) {
      note = document.createElement('div');
      note.className = 'igt-composer-note';
      // Above the composer's row so Instagram's own layout stays intact.
      (c.closest('form, [role="group"]') || c.parentElement).before(note);
    }
    note.classList.toggle('igt-error', !!isError);
    note.replaceChildren(...nodes);
  };
  const hideNote = () => { note?.remove(); note = null; };

  const chip = (lang) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'igt-chip';
    b.textContent = langName(lang);
    b.title = 'Change target language';
    b.onclick = (e) => {
      e.preventDefault();
      const sel = document.createElement('select');
      sel.className = 'igt-chip';
      for (const [code, name] of Object.entries(LANG_NAMES)) if (code !== 'ko') sel.add(new Option(name, code));
      if (!(lang in LANG_NAMES)) sel.add(new Option(langName(lang), lang), 0); // partner language outside the list
      sel.value = lang;
      sel.onchange = async () => {
        const c = getCurrent();
        try {
          if (c) c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch: { outputLang: sel.value } });
        } catch (err) {
          showBanner(`ig-translate: could not save the reply language: ${err.message}`);
        }
        dispatch({ type: 'lang', lang: sel.value });
      };
      b.replaceWith(sel);
      sel.focus();
    };
    return b;
  };

  function resetPreview() {
    dispatch({ type: 'reset' });
    hideNote();
    lastText = '';
  }

  async function apply(effect) {
    const c = composer();
    switch (effect.type) {
      case 'translate': {
        showNote([text(effect.profile === 'hard' ? 'Translating (hard)...' : 'Translating...')]);
        try {
          const cur2 = getCurrent();
          if (!cur2) throw new Error('thread closed');
          const r = await ask({
            type: 'outgoing', threadId: cur2.threadId, context: contextFor(cur2.root),
            korean: effect.korean, profile: effect.profile, lang: effect.lang,
          });
          dispatch({ type: 'result', reqId: effect.reqId, ...r });
        } catch (e) {
          if (bannerFor(e)) showBanner(bannerFor(e));
          dispatch({ type: 'fail', reqId: effect.reqId, message: e.message });
        }
        break;
      }
      case 'show': {
        if (!c) { resetPreview(); break; }
        await write(c, effect.translation);
        await new Promise((r) => setTimeout(r, WRITE_SETTLE_MS));
        if (state.mode !== 'preview') break; // Esc or reset meanwhile
        if (norm(getComposerText(c)) !== norm(effect.translation)) {
          dispatch({ type: 'reset' });
          showNote([text('Could not write the translation into the message box. Nothing was sent.')], true);
          break;
        }
        lastText = effect.translation;
        showNote([text(`${effect.back_translation}  · ${modelLabel(effect.model)}`), chip(effect.lang)]);
        break;
      }
      case 'restore':
        if (c) await write(c, effect.korean);
        hideNote();
        lastText = '';
        break;
      case 'sent': {
        // Runs synchronously inside the Enter keydown, before Instagram reads and clears the composer.
        const cur2 = getCurrent();
        const sentText = c ? getComposerText(c).trim() : '';
        hideNote();
        lastText = '';
        if (cur2 && sentText) ask({ type: 'sent', threadId: cur2.threadId, text: sentText, korean: effect.korean }).catch(() => {});
        break;
      }
      case 'fail':
        if (c && effect.korean != null && norm(getComposerText(c)) !== norm(effect.korean)) await write(c, effect.korean);
        lastText = '';
        showNote([text(`Translation failed: ${effect.message}`)], true);
        break;
    }
  }

  function dispatch(event) {
    const r = reduce(state, event);
    state = r.state;
    apply(r.effect);
    return r.effect;
  }

  // Composer emptied while previewing: Instagram's Send button sent it, or the user deleted it.
  function checkEmpty() {
    if (state.mode !== 'preview') return;
    const c = composer();
    if (!c || getComposerText(c).trim() !== '') return;
    const cur2 = getCurrent();
    if (cur2 && lastText.trim()) {
      ask({ type: 'sent', threadId: cur2.threadId, text: lastText.trim(), korean: state.korean }).catch(() => {});
    }
    resetPreview();
  }

  function onInput(e) {
    const c = composer();
    if (writing || state.mode !== 'preview' || !c || !c.contains(e.target)) return;
    const t = getComposerText(c);
    if (t.trim()) lastText = t; else checkEmpty();
  }

  function onKeyDown(e) {
    const cur2 = getCurrent();
    if (!cur2?.thread.enabled) return;
    const c = composer();

    if (!c || !c.contains(e.target)) {
      // Composer selector broken: never let Hangul go out untranslated by accident.
      if (!c && isEnter(e) && !e.shiftKey && e.target?.isContentEditable
          && hasHangul(e.target.innerText || e.target.textContent || '')) {
        block(e);
        showBanner('ig-translate: message box not recognised, so nothing was sent. The selectors need updating.');
      }
      return;
    }

    if (e.key === 'Escape') {
      const eff = dispatch({ type: 'esc' });
      if (eff.type !== 'pass') block(e);
      return;
    }
    if (!isEnter(e) || e.shiftKey) return;

    // Korean IME: Enter mid-composition. Never let it reach Instagram while a translation is pending
    // or while the box holds Hangul; handle the Enter once the composition is committed.
    if (e.isComposing || e.keyCode === 229) {
      if (state.mode === 'translating') { block(e); return; }
      if (hasHangul(getComposerText(c)) && !(state.mode === 'preview' && state.lang === 'ko')) {
        block(e);
        enterAfterComposition = { hard: e.altKey, at: Date.now() };
      }
      return;
    }

    const eff = dispatch({ type: 'enter', text: getComposerText(c), hard: e.altKey });
    // 'sent' lets the real Enter through so Instagram sends the composer text itself.
    if (eff.type !== 'pass' && eff.type !== 'sent') block(e);
  }

  function onCompositionEnd() {
    const pending = enterAfterComposition;
    enterAfterComposition = null;
    if (!pending || Date.now() - pending.at > COMPOSE_ENTER_MS) return;
    // Let the committed text land in the composer first.
    setTimeout(() => {
      const c = composer();
      if (c) dispatch({ type: 'enter', text: getComposerText(c), hard: pending.hard });
    }, 0);
  }

  window.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('compositionend', onCompositionEnd, true);
  window.addEventListener('input', onInput, true);
  cur.onMutate.push(checkEmpty);
  cur.onThreadUpdate.push((t) => { if (!t.enabled && state.mode !== 'idle') resetPreview(); });
  cur.onTeardown.push(() => {
    window.removeEventListener('keydown', onKeyDown, true);
    window.removeEventListener('compositionend', onCompositionEnd, true);
    window.removeEventListener('input', onInput, true);
    resetPreview();
  });
}
