import { initial, reduce } from '../lib/preview.js';
import { hasHangul, langName, LANG_NAMES } from '../lib/lang.js';
import { findComposer, getComposerText, setComposerText } from './dom.js';
import { ask, getCurrent, contextFor, showBanner, bannerFor } from './main.js';
import { threadIdFromPath } from '../lib/keys.js';
import { flags } from '../lib/flags.js';

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
  let writing = false; // a composer write is queued or running: its input events are ours, and Enter/Esc wait
  let writeGen = 0;
  let writeChain = Promise.resolve();
  let srcText = ''; // composer text when the current translation was requested
  let composing = false;
  let dead = false;

  // This mount still owns the page: not torn down and the URL still shows its thread. Between a thread
  // switch and the next 500 ms tick, composer() already finds the NEW thread's box.
  const live = () => !dead && getCurrent() === cur && threadIdFromPath(location.pathname) === cur.threadId;
  const composer = () => findComposer(document);
  const text = (s) => document.createTextNode(s);
  // Writes run one at a time; a newer write supersedes queued or settling older ones.
  const write = (c, s) => {
    const gen = ++writeGen;
    writing = true;
    writeChain = writeChain.then(async () => {
      if (gen !== writeGen || !live()) return false;
      return setComposerText(c, s, () => gen === writeGen && live());
    }).catch(() => false).finally(() => { if (gen === writeGen) writing = false; });
    return writeChain;
  };

  // Composer selector check (design: selector miss = inactive + badge).
  setTimeout(() => {
    if (getCurrent() === cur && !composer()) {
      ask({ type: 'badge', text: '!' }).catch(() => {});
      console.warn('[protly] composer not found; outgoing translation inactive');
    }
  }, 3000);

  const showNote = (nodes, isError) => {
    const c = composer();
    if (!c) return;
    if (!note) {
      note = document.createElement('div');
      note.className = 'pl-composer-note';
      // Above the composer's row so Instagram's own layout stays intact.
      (c.closest('form, [role="group"]') || c.parentElement).before(note);
    }
    note.classList.toggle('pl-error', !!isError);
    note.replaceChildren(...nodes);
  };
  const hideNote = () => { note?.remove(); note = null; };

  const chip = (lang) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'pl-chip';
    b.textContent = langName(lang);
    b.title = 'Change target language';
    b.onclick = (e) => {
      e.preventDefault();
      const sel = document.createElement('select');
      sel.className = 'pl-chip';
      for (const [code, name] of Object.entries(LANG_NAMES)) if (code !== 'ko') sel.add(new Option(name, code));
      if (!(lang in LANG_NAMES)) sel.add(new Option(langName(lang), lang), 0); // partner language outside the list
      sel.value = lang;
      sel.onchange = async () => {
        const c = getCurrent();
        try {
          if (c) c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch: { outputLang: sel.value } });
        } catch (err) {
          showBanner(`protly: could not save the reply language: ${err.message}`);
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
    if (!live()) return; // a late result must never touch another thread's composer
    const c = composer();
    switch (effect.type) {
      case 'translate': {
        if (c) srcText = getComposerText(c);
        const verb = effect.kind === 'polish' ? 'Polishing' : 'Translating';
        showNote([text(effect.profile === 'hard' ? `${verb} (Opus)...` : `${verb}...`)]);
        try {
          const cur2 = getCurrent();
          if (!cur2) throw new Error('thread closed');
          const r = effect.kind === 'polish'
            ? await ask({ type: 'polish', text: effect.korean, profile: effect.profile })
            : await ask({
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
        // The draft changed while translating (typing, or Instagram's Send button sent it): drop the result.
        if (norm(getComposerText(c)) !== norm(srcText)) {
          dispatch({ type: 'reset' });
          showNote([text('The draft changed while translating, so the translation was dropped. Press Enter again.')], true);
          break;
        }
        const korean = state.korean;
        const ok = await write(c, effect.translation);
        await new Promise((r) => setTimeout(r, WRITE_SETTLE_MS));
        if (!live() || state.mode !== 'preview') break; // Esc, reset or thread switch meanwhile
        if (!ok || norm(getComposerText(c)) !== norm(effect.translation)) {
          dispatch({ type: 'reset' });
          if (korean) await write(c, korean); // never leave an unpreviewed translation behind
          showNote([text('Could not write the translation into the message box. Nothing was sent.')], true);
          break;
        }
        lastText = effect.translation;
        const label = text(`${effect.back_translation}  · ${modelLabel(effect.model)}`);
        showNote(state.kind === 'polish' ? [label] : [label, chip(effect.lang)]); // no target language to pick
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
    if (!live()) return; // main.js guards Hangul Enter until the new thread's handler is mounted
    const cur2 = getCurrent();
    if (!cur2?.thread.enabled) return;
    const c = composer();

    if (!c || !c.contains(e.target)) {
      // Composer selector broken: never let Hangul go out untranslated by accident.
      if (!c && isEnter(e) && !e.shiftKey && e.target?.isContentEditable
          && hasHangul(e.target.innerText || e.target.textContent || '')) {
        block(e);
        showBanner('protly: message box not recognised, so nothing was sent. The selectors need updating.');
      }
      return;
    }

    // A write is landing: the composer does not yet match the state, so Enter/Esc would act on stale text.
    if (writing && (e.key === 'Escape' || isEnter(e))) { block(e); return; }
    if (isEnter(e) && e.repeat) { block(e); return; } // a held Enter must not confirm a preview it never showed

    if (e.key === 'Escape') {
      const eff = dispatch({ type: 'esc' });
      if (eff.type !== 'pass') block(e);
      return;
    }
    if (!isEnter(e) || e.shiftKey) return;

    // Korean IME: Enter mid-composition. Never let it reach Instagram while a translation is pending
    // or while the box holds Hangul; handle the Enter once the composition is committed.
    if (e.isComposing || composing) {
      if (state.mode === 'translating') { block(e); return; }
      if (hasHangul(getComposerText(c)) && !(state.mode === 'preview' && state.lang === 'ko')) {
        block(e);
        enterAfterComposition = { hard: e.altKey, at: Date.now() };
      }
      return;
    }

    const eff = dispatch({ type: 'enter', text: getComposerText(c), hard: e.altKey, polish: flags.polish });
    // 'sent' lets the real Enter through so Instagram sends the composer text itself.
    if (eff.type !== 'pass' && eff.type !== 'sent') block(e);
  }

  function onCompositionStart() { composing = true; }
  function onCompositionEnd() {
    composing = false;
    const pending = enterAfterComposition;
    enterAfterComposition = null;
    if (!pending || Date.now() - pending.at > COMPOSE_ENTER_MS) return;
    // Let the committed text land in the composer first.
    setTimeout(() => {
      const c = composer();
      if (!c || !live()) return;
      const ev = { type: 'enter', text: getComposerText(c), hard: pending.hard, polish: flags.polish };
      // The real Enter was blocked, so a deferred 'sent' or 'pass' would send nothing: ask for another Enter.
      const kind = reduce(state, ev).effect.type;
      if (kind === 'sent' || kind === 'pass') { showNote([text('Press Enter again to send.')]); return; }
      dispatch(ev);
    }, 0);
  }

  window.addEventListener('keydown', onKeyDown, true);
  window.addEventListener('compositionstart', onCompositionStart, true);
  window.addEventListener('compositionend', onCompositionEnd, true);
  window.addEventListener('input', onInput, true);
  cur.onMutate.push(checkEmpty);
  cur.onThreadUpdate.push((t) => { if (!t.enabled && state.mode !== 'idle') resetPreview(); });
  cur.onTeardown.push(() => {
    window.removeEventListener('keydown', onKeyDown, true);
    window.removeEventListener('compositionstart', onCompositionStart, true);
    window.removeEventListener('compositionend', onCompositionEnd, true);
    window.removeEventListener('input', onInput, true);
    resetPreview();
    dead = true;
  });
}
