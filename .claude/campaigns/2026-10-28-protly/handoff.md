# protly campaign handoff

- Phase: COMPLETE 2026-10-28. Sprint 4 (any-site Alt+T) DONE: commits 60acfaf..7a51a88 (incl. review fixes d5e665e, 7a51a88), npm test 285 pass / 0 fail, Python 21 OK. Spec SPEC_COMPLIANT, quality findings 1-10 fixed. User live check on the local test page and real sites: works ("seems to work fine").
- Sprint 3 (popup, usage, options) DONE 2026-10-28: commits 90f12d0..16dc23c, npm test 212 pass / 0 fail, Python 21 OK. Spec SPEC_COMPLIANT, quality fixes in 16dc23c, user live check passed (options auto-save, Check host, Test call, popup status/cost, Gmail switch off/on, generic page).
- Next: nothing queued.
- Sprint 2 live fixes: card theme follows its surroundings (ea352d4, Gmail compose is white on a dark page); composer check retries 10 s before warning (33522c4, user saw a false 'composer not found' at outgoing.js:47).
- Plan: docs/plans/2026-10-28-protly.md (theme.js contract updated in ea352d4). Design: docs/plans/2026-10-28-protly-design.md.
- Repo /home/cyan/projects/protly. Extension ID X = idkdlhcfhfdbbpakkaifjlmjhhfepidg (manifest key; private key ~/.config/protly/extension-key.pem, never committed).
- Storage backup of the old ID deleted 2026-10-28 at the user's call (campaign closed).
- Claude in Chrome cannot open chrome-extension:// pages; check from the page side.
- Parallel agents in one tree: commit with `git add <paths> && git commit -- <paths>` so nobody sweeps another agent's staged files.
- Gmail live-test gotcha: clicking the compose body by ref can hit the title bar and minimize it; focus the body via JS and click Translate via JS (Send is right next to it).
- Never press Enter or Send in Instagram or Gmail composers. Never push. Never print the API key.
