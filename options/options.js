import { DEFAULT_SETTINGS } from '../src/lib/keys.js';

const MODELS = ['claude-sonnet-5-5', 'claude-opus-5-5'];
const $ = (id) => document.getElementById(id);

for (const id of ['incoming', 'outgoing', 'hard']) {
  for (const m of MODELS) $(id).add(new Option(m, m));
}

const { settings = {} } = await chrome.storage.local.get('settings');
const models = { ...DEFAULT_SETTINGS.models, ...settings.models };
const threadDefaults = { ...DEFAULT_SETTINGS.threadDefaults, ...settings.threadDefaults };
for (const id of ['incoming', 'outgoing', 'hard']) $(id).value = MODELS.includes(models[id]) ? models[id] : DEFAULT_SETTINGS.models[id];
for (const id of ['otherTarget', 'pastMode', 'newMode']) $(id).value = threadDefaults[id];

$('save').onclick = async () => {
  await chrome.storage.local.set({
    settings: {
      models: { incoming: $('incoming').value, outgoing: $('outgoing').value, hard: $('hard').value },
      threadDefaults: { otherTarget: $('otherTarget').value, pastMode: $('pastMode').value, newMode: $('newMode').value },
    },
  });
  $('saved').textContent = 'Saved';
  setTimeout(() => { $('saved').textContent = ''; }, 1500);
};
