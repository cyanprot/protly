export const TOAST_CSS = `
.list { position: fixed; top: 12px; right: 12px; z-index: 2147483647; display: flex; flex-direction: column; gap: 6px;
  max-width: 360px; background: none; }
.toast { display: flex; gap: 8px; align-items: baseline; padding: 8px 12px; cursor: pointer;
  background: var(--pl-bg); color: var(--pl-fg); border: 1px solid var(--pl-rule); border-radius: var(--pl-radius); }
.toast .label { font-weight: 500; color: var(--pl-muted); }
.toast .msg { white-space: pre-wrap; font-family: var(--pl-font), system-ui, sans-serif; }
.toast.err .msg { color: var(--pl-err); }
`;
