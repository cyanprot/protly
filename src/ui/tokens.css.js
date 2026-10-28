// northprot brand: ink and paper only, red for errors only. No shadows, no gradients; elevation is a 1px rule.
// Used inside shadow roots (Instagram, Gmail, generic) and adopted by the popup and options pages.
export const TOKENS = `
:host, .pl-root {
  --pl-paper: #F5F0E6;
  --pl-ink: #1A1F2E;
  --pl-bg: var(--pl-paper);
  --pl-fg: var(--pl-ink);
  --pl-muted: rgb(26 31 46 / .6);
  --pl-rule: rgb(26 31 46 / .15);
  --pl-err: #B3261E;
  --pl-font: protly-mono, ui-monospace, SFMono-Regular, Menlo, monospace;
  --pl-radius: 4px;
}
.pl-root[data-pl-theme=dark] {
  --pl-bg: var(--pl-ink);
  --pl-fg: var(--pl-paper);
  --pl-muted: rgb(245 240 230 / .6);
  --pl-rule: rgb(245 240 230 / .18);
  --pl-err: #FF8A80;
}
`;

export const BASE = `
:host { all: initial; }
.pl-root { font: 400 12px/1.45 var(--pl-font); color: var(--pl-fg); background: var(--pl-bg); }
.pl-root button, .pl-root select, .pl-btn, .pl-chip {
  font: 500 12px/1.2 var(--pl-font); color: var(--pl-fg); background: var(--pl-bg);
  border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); padding: 3px 8px; margin: 0; cursor: pointer;
}
.pl-root button:hover, .pl-root select:hover { border-color: var(--pl-fg); }
.pl-root button:focus-visible, .pl-root select:focus-visible { outline: 1px solid var(--pl-fg); outline-offset: 1px; }
.pl-root button:disabled { color: var(--pl-muted); cursor: default; }
.pl-chip { border-radius: 999px; padding: 1px 8px; }
.pl-kbd { font: 500 11px var(--pl-font); color: var(--pl-muted); }
`;
