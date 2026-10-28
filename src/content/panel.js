import { ask, rerender, getCurrent, contextFor, showBanner } from './main.js';
import { LANG_NAMES } from '../lib/lang.js';

export function mountPanel(cur) {
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;right:16px;bottom:96px;z-index:99998';
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      button.fab { width: 36px; height: 36px; border-radius: 18px; border: 0; background: #3a3a3c; color: #fff; cursor: pointer; font: 600 13px system-ui; }
      .p { display: none; position: absolute; right: 0; bottom: 44px; width: 280px; background: #1c1c1e; color: #f2f2f7; border-radius: 10px; padding: 12px; font: 13px system-ui; box-shadow: 0 4px 16px #0006; }
      .p.open { display: block; }
      label { display: flex; justify-content: space-between; align-items: center; margin: 6px 0; gap: 8px; }
      select, textarea { background: #2c2c2e; color: inherit; border: 1px solid #48484a; border-radius: 6px; font: inherit; }
      textarea { width: 100%; box-sizing: border-box; height: 90px; margin-top: 4px; }
      .row { display: flex; gap: 6px; margin-top: 6px; }
      .row button { flex: 1; background: #2c2c2e; color: inherit; border: 1px solid #48484a; border-radius: 6px; padding: 4px; cursor: pointer; }
    </style>
    <button type="button" class="fab" title="protly">T</button>
    <div class="p">
      <label>Translate <input type="checkbox" id="enabled"></label>
      <label>Reply in <select id="outputLang"></select></label>
      <label>Other languages to <select id="otherTarget"><option value="ko">Korean</option><option value="en">English</option></select></label>
      <label>Past messages <select id="pastMode"><option value="replace">Replace</option><option value="below">Below</option></select></label>
      <label>New messages <select id="newMode"><option value="below">Below</option><option value="replace">Replace</option></select></label>
      <div>Memo</div>
      <textarea id="memo" placeholder="Who they are, tone, nicknames, running jokes"></textarea>
      <div class="row"><button type="button" id="suggest">Suggest memo</button><button type="button" id="saveMemo">Save memo</button></div>
    </div>`;
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

  shadow.querySelector('.fab').onclick = () => {
    shadow.querySelector('.p').classList.toggle('open');
    fill(getCurrent()?.thread || cur.thread); // pick up partnerLang/outputLang changes
  };

  const save = async (patch, rerenderAfter) => {
    const c = getCurrent();
    if (!c) return;
    try {
      c.thread = await ask({ type: 'setThread', threadId: c.threadId, patch });
    } catch (e) {
      showBanner(`protly: could not save: ${e.message}`);
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
      showBanner(`protly: memo suggestion failed: ${e.message}`);
    } finally {
      $('suggest').disabled = false;
    }
  };

  document.body.appendChild(host);
  cur.onTeardown.push(() => host.remove());
}
