import { DEFAULT_SETTINGS } from '../src/lib/keys.js';
import { stylePage, ask } from '../src/ui/page.js';
import { errorText } from '../src/ui/errors.js';

stylePage();
const MODELS = ['claude-sonnet-5-5', 'claude-opus-5-5'];
const MODEL_IDS = ['incoming', 'outgoing', 'hard'];
const DEFAULT_IDS = ['otherTarget', 'pastMode', 'newMode'];
const $ = (id) => document.getElementById(id);

for (const id of MODEL_IDS) for (const m of MODELS) $(id).add(new Option(m, m));

const { settings = {} } = await chrome.storage.local.get('settings');
const models = { ...DEFAULT_SETTINGS.models, ...settings.models };
const threadDefaults = { ...DEFAULT_SETTINGS.threadDefaults, ...settings.threadDefaults };
for (const id of MODEL_IDS) $(id).value = MODELS.includes(models[id]) ? models[id] : DEFAULT_SETTINGS.models[id];
for (const id of DEFAULT_IDS) $(id).value = threadDefaults[id];

let savedTimer = null;
async function save() {
  const { settings: current = {} } = await chrome.storage.local.get('settings');
  await chrome.storage.local.set({
    settings: {
      ...current,
      models: Object.fromEntries(MODEL_IDS.map((id) => [id, $(id).value])),
      threadDefaults: Object.fromEntries(DEFAULT_IDS.map((id) => [id, $(id).value])),
    },
  });
  $('saved').textContent = ' Saved.';
  clearTimeout(savedTimer);
  savedTimer = setTimeout(() => { $('saved').textContent = ''; }, 1500);
}
for (const id of [...MODEL_IDS, ...DEFAULT_IDS]) $(id).addEventListener('change', save);

$('ext-id').textContent = chrome.runtime.id;

function show(id, text, isError = false) {
  $(id).textContent = text;
  $(id).classList.toggle('err', isError);
}

$('check').onclick = async () => {
  show('host-result', 'Checking...');
  try {
    const p = await ask({ type: 'diag' });
    const parts = [
      'Host OK',
      p.key_present ? 'API key found' : 'API key MISSING',
      p.workspace_header ? 'workspace header on' : 'no workspace header',
    ];
    show('host-result', parts.join(' · '), !p.key_present);
  } catch (e) {
    show('host-result', e.kind === 'host' ? `Host not reachable: ${e.message}` : errorText(e), true);
  }
};

$('test').onclick = async () => {
  $('test').disabled = true;
  show('test-result', 'Calling...');
  try {
    const r = await ask({ type: 'testCall' });
    show('test-result', `${r.model} · ${r.ms} ms`);
  } catch (e) {
    show('test-result', errorText(e), true);
  } finally {
    $('test').disabled = false;
  }
};
