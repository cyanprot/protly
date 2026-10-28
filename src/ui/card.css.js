export const CARD_CSS = `
.pl-root { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 8px; box-sizing: border-box; max-width: 560px;
  padding: 6px 10px; border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); }
.msg { flex: 1 1 220px; white-space: pre-wrap; font-family: var(--pl-font), system-ui, sans-serif; }
.err .msg { color: var(--pl-err); }
.model { color: var(--pl-muted); }
.hints { flex-basis: 100%; color: var(--pl-muted); font-size: 11px; }
.dots::after { content: ''; animation: pl-dots 1.2s steps(1) infinite; }
@keyframes pl-dots { 0% { content: ''; } 25% { content: '.'; } 50% { content: '..'; } 75% { content: '...'; } }
@media (prefers-reduced-motion: reduce) { .dots::after { animation: none; content: '...'; } }
`;
