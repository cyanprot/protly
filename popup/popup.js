import { stylePage, ask } from '../src/ui/page.js';
import { DEFAULT_SITES } from '../src/lib/flags.js';
import { formatUsd } from '../src/lib/usage.js';

stylePage();
const $ = (id) => document.getElementById(id);

const { polish, sites: stored } = await chrome.storage.local.get(['polish', 'sites']);
const sites = { ...DEFAULT_SITES, ...stored };
$('polish').checked = polish === true;
$('site-instagram').checked = sites.instagram;
$('site-gmail').checked = sites.gmail;

$('polish').onchange = () => chrome.storage.local.set({ polish: $('polish').checked });
const saveSites = async () => {
  await chrome.storage.local.set({
    sites: { instagram: $('site-instagram').checked, gmail: $('site-gmail').checked },
  });
  showStatus();
};
$('site-instagram').onchange = saveSites;
$('site-gmail').onchange = saveSites;

$('options').onclick = () => chrome.runtime.openOptionsPage();

async function showStatus() {
  const el = $('status');
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const s = await ask({ type: 'tabStatus', tabId: tab?.id, url: tab?.url });
    el.textContent = s.text;
    el.dataset.state = s.state;
  } catch (e) {
    el.textContent = `Status unknown: ${e.message}`;
    el.dataset.state = 'problem';
  }
}

async function showUsage() {
  try {
    const u = await ask({ type: 'usageSummary' });
    $('today').textContent = formatUsd(u.today, u.unpriced);
    $('month').textContent = formatUsd(u.month, u.unpriced);
    if (u.unpriced) $('month').title = 'A model without a known price was used; its cost is not included.';
  } catch {
    $('today').textContent = $('month').textContent = '?';
  }
}

showStatus();
showUsage();
