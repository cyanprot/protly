// Instagram thread panel: a square p tile (1px rule) that opens the thread settings as a card.
export const PANEL_CSS = `
.pl-root { background: none; }
.fab { width: 32px; height: 32px; padding: 0; display: grid; place-items: center;
  font: 500 17px/1 var(--pl-font); color: var(--pl-fg); background: var(--pl-bg);
  border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); cursor: pointer; }
.fab:hover, .fab[aria-expanded=true] { border-color: var(--pl-fg); }
.p { display: none; position: absolute; right: 0; bottom: 40px; width: 288px; box-sizing: border-box; padding: 10px 12px;
  background: var(--pl-bg); color: var(--pl-fg); border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); }
.p.open { display: block; }
.head { font-weight: 500; margin-bottom: 6px; padding-bottom: 6px; border-bottom: 1px solid var(--pl-rule); }
label { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin: 6px 0; }
.memo-label { margin-top: 10px; color: var(--pl-muted); }
textarea { width: 100%; box-sizing: border-box; height: 90px; margin-top: 4px; padding: 6px; resize: vertical;
  font: 400 12px/1.4 var(--pl-font), system-ui, sans-serif; color: var(--pl-fg); background: var(--pl-bg);
  border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); }
textarea:focus { outline: 1px solid var(--pl-fg); }
input[type=checkbox] { accent-color: var(--pl-fg); }
.row { display: flex; gap: 6px; margin-top: 6px; }
.row button { flex: 1; }
`;
