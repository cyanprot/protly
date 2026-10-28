const box = document.getElementById('polish');
box.checked = (await chrome.storage.local.get('polish')).polish === true;
box.onchange = () => chrome.storage.local.set({ polish: box.checked });
