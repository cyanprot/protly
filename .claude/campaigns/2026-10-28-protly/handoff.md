# protly campaign handoff

- Phase: execute. Sprint 2 (design system) code DONE 2026-10-28 (Tasks 2.1-2.10 + review fixes, commits 2d78875..ea352d4, npm test 175 pass / 0 fail, Python OK). Spec review SPEC_COMPLIANT; quality review fixes landed (5a043da, c80c92a); live theme fix ea352d4 (card theme follows its surroundings: Gmail compose is white on a dark page).
- Task 2.11 live check, done by Claude 2026-10-28: fonts load on both sites (no CSP issue), Instagram p tile + panel dark ink/paper in protly-mono, translated messages keep the site font, Gmail working card + preview card (label, chip, Opus/Undo, Esc undo) right, Gmail Esc restores Korean and keeps compose open, test draft discarded.
- Task 2.11 still open (needs the user): reload protly after ea352d4; user types a Korean Instagram draft and presses Enter (Claude never does); check the Instagram card (back-translation, model, chip, `Enter send · Esc undo · Alt+Enter Opus`), Esc undo, Gmail card now light inside the white compose, toolbar p icon.
- Then close Sprint 2 (campaign.json completed_sprints, current_sprint 3) and start Sprint 3 Task 3.1.
- Plan: docs/plans/2026-10-28-protly.md (theme.js contract updated in ea352d4). Design: docs/plans/2026-10-28-protly-design.md.
- Repo /home/cyan/projects/protly. Extension ID X = idkdlhcfhfdbbpakkaifjlmjhhfepidg (manifest key; private key ~/.config/protly/extension-key.pem, never committed).
- Storage backup of the old ID: ~/.config/protly/storage-backup-dcfndjml/ (keep until campaign closes).
- Claude in Chrome cannot open chrome-extension:// pages; check from the page side.
- Gmail live-test gotcha: clicking the compose body by ref can hit the title bar and minimize it; focus the body via JS and click Translate via JS (Send is right next to it).
- Never press Enter or Send in Instagram or Gmail composers. Never push. Never print the API key.
