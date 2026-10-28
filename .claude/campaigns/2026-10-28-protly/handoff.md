# protly campaign handoff

- Phase: execute. Sprint 1 (rename) DONE 2026-10-28 and verified live; next is Sprint 2 (design system), Task 2.1.
- Plan: docs/plans/2026-10-28-protly.md (header holds the binding shared contracts). Design: docs/plans/2026-10-28-protly-design.md.
- Repo now at /home/cyan/projects/protly. Extension ID X = idkdlhcfhfdbbpakkaifjlmjhhfepidg (manifest key; private key ~/.config/protly/extension-key.pem, never committed).
- Storage backup of the old ID: ~/.config/protly/storage-backup-dcfndjml/ (keep until campaign closes; deleting is the user's call).
- Old ig-translate card vanished from chrome://extensions by itself after the move; its storage folder and Preferences entry still exist. Harmless; Claude never edits Preferences.
- Claude in Chrome cannot open chrome-extension:// pages (Task 3.9 probe already answered: use the user fallback or the page-side check).
- Exit checks passed: loaded ID == X, stored memo present (thread 17846068155161024), Suggest memo went through com.northprot.protly, .pl-tr rendered.
- Never press Enter or Send in Instagram or Gmail composers. Never push. Never print the API key. Plan test counts approximate; gate is fail 0 + Python OK.
