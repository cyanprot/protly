import { ask, rerender, getCurrent, contextFor } from './main.js';
import { LANG_NAMES } from '../lib/lang.js';
import { TOKENS, BASE } from '../ui/tokens.css.js';
import { PANEL_CSS } from '../ui/panel.css.js';
import { bindTheme } from '../ui/theme.js';
import { showToast } from '../ui/toast.js';
import { errorText } from '../ui/errors.js';

export function mountPanel(cur) {
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;right:16px;bottom:96px;z-index:99998';
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>${TOKENS}${BASE}${PANEL_CSS}</style>
    <div class="pl-root">
      <button type="button" class="fab" title="protly: this thread" aria-expanded="false">p</button>
      <div class="p" role="dialog" aria-label="protly thread settings">
        <div class="head">protly</div>
        <label>Translate <input type="checkbox" id="enabled"></label>
        <label>Reply in <select id="outputLang"></select></label>
        <label>Other languages to <select id="otherTarget"><option value="ko">Korean</option><option value="en">English</option></select></label>
        <label>Past messages <select id="pastMode"><option value="replace">Replace</option><option value="below">Below</option></select></label>
        <label>New messages <select id="newMode"><option value="below">Below</option><option value="replace">Replace</option></select></label>
        <div class="memo-label">Memo</div>
        <textarea id="memo" placeholder="Who they are, tone, nicknames, running jokes"></textarea>
        <div class="row"><button type="button" id="suggest">Suggest memo</button><button type="button" id="saveMemo">Save memo</button></div>
      </div>
    </div>`;
  const unbindTheme = bindTheme(shadow.querySelector('.pl-root'), document);
  const $ = (id) => shadow.getElementById(id);
  const out = $('outputLang');
  out.add(new Option('Auto', 'auto'));
  for (const [code, name] of Object.entries(LANG_NAMES)) if (code !== 'ko') out.add(new Option(name, code));

  const fill = (t) => {
    $('enabled').checked = t.enabled;
    out.value = t.outputLang;
    for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).value = t[id];
    $('memo').value = t.memo;
  };
  fill(cur.thread);

  const fab = shadow.querySelector('.fab');
  fab.onclick = () => {
    const open = shadow.querySelector('.p').classList.toggle('open');
    fab.setAttribute('aria-expanded', String(open));
    fill(getCurrent()?.thread || cur.thread); // pick up partnerLang/outputLang changes
  };

  const save = async (patch, rerenderAfter) => {
    const c = getCurrent();
    if (!c) return;
    try {
      c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch });
    } catch (e) {
      showToast(`Could not save: ${errorText(e)}`, { transient: true, error: true });
      fill(c.thread); // show what is actually stored
      return;
    }
    c.onThreadUpdate.forEach((f) => f(c.thread)); // e.g. outgoing resets its preview when disabled
    if (rerenderAfter) rerender();
  };
  $('enabled').onchange = () => save({ enabled: $('enabled').checked }, true);
  out.onchange = () => save({ outputLang: out.value }, false);
  for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).onchange = () => save({ [id]: $(id).value }, true);
  $('saveMemo').onclick = () => save({ memo: $('memo').value }, false);
  $('suggest').onclick = async () => {
    const c = getCurrent();
    if (!c) return;
    $('suggest').disabled = true;
    try {
      $('memo').value = await ask({ type: 'suggestMemo', threadId: c.threadId, context: contextFor(c.root) });
    } catch (e) {
      showToast(`Memo suggestion failed: ${errorText(e)}`, { transient: true, error: true });
    } finally {
      $('suggest').disabled = false;
    }
  };

  document.body.appendChild(host);
  cur.onTeardown.push(() => { unbindTheme(); host.remove(); });
}
