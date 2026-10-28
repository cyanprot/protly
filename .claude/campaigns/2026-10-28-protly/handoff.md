# protly campaign handoff

- Phase: execute. Sprint 2 (design system) DONE 2026-10-28: commits 2d78875..33522c4, npm test 175 pass / 0 fail, Python OK. Spec review SPEC_COMPLIANT, quality fixes landed, live check passed (Claude: panel, fonts, Gmail cards, Gmail Esc; user: Instagram Enter flow works as before).
- Next: Sprint 3 (popup, usage, options), Task 3.1 of docs/plans/2026-10-28-protly.md.
- Sprint 2 live fixes: card theme follows its surroundings (ea352d4, Gmail compose is white on a dark page); composer check retries 10 s before warning (33522c4, user saw a false 'composer not found' at outgoing.js:47).
- Plan: docs/plans/2026-10-28-protly.md (theme.js contract updated in ea352d4). Design: docs/plans/2026-10-28-protly-design.md.
- Repo /home/cyan/projects/protly. Extension ID X = idkdlhcfhfdbbpakkaifjlmjhhfepidg (manifest key; private key ~/.config/protly/extension-key.pem, never committed).
- Storage backup of the old ID: ~/.config/protly/storage-backup-dcfndjml/ (keep until campaign closes).
- Claude in Chrome cannot open chrome-extension:// pages; check from the page side.
- Parallel agents in one tree: commit with `git add <paths> && git commit -- <paths>` so nobody sweeps another agent's staged files.
- Gmail live-test gotcha: clicking the compose body by ref can hit the title bar and minimize it; focus the body via JS and click Translate via JS (Send is right next to it).
- Never press Enter or Send in Instagram or Gmail composers. Never push. Never print the API key.
