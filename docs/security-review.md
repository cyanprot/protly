# Security review: Chrome extension and native host

Campaign 2026-10-29-security-review, Sprint 001. Plan: `docs/plans/2026-10-29-security-review.md`. The findings
table (E1-E14, H1-H2, R1-R10) and the flight report are in the body of PR #2 (`gh pr view 2 --repo
cyanprot/protly`). The iPhone side is in `docs/security-review-ios.md`.

## Tower follow-ups (branch `sec-followups`)

- The Instagram outgoing handler's untrusted-Enter guard is now tested through the mounted handler
  (`tests/outgoing.test.js`), not only through `holdUntrustedEnter()`.
- R7: the generic instance lives under `globalThis[Symbol.for('protly')]` in `src/generic/run.js` and the
  background's `executeScript` funcs.
- R3, in part: the host's ping reports `key_shared` when `~/.config/anthropic/api-key` has group or other
  permission bits (mode only), and Diagnostics shows a `chmod 600` hint.
- iOS Q6: `tests/make-secrets.test.js` runs `ios-app/scripts/make-secrets.sh` with a fake HOME and key.
- The any-site box, polish and selection paths already refuse text over 8000 characters with a "Too long"
  toast before any request (`src/generic/instance.js` `MAX_CHARS`, tests in `tests/generic-instance.test.js`
  and `tests/hostile-page.test.js`), below `LIMITS.text`, so no change was needed there.

## Tower decisions

- **R1, storage access level:** no. Restricting `chrome.storage.local` to trusted contexts is a design change;
  it stays an open item.
- **R2, retry after a port disconnect:** keep the retry, so a host cold start still recovers on its own; the
  possible double bill is accepted.
- **R3, host body allowlist:** no. The host forwards bodies as they are; only the key file mode warning above
  was added.
- **R8, `use_dynamic_url`:** no.
- **R9, `host_permissions` for instagram.com:** pending a Chrome check. Drop it only after Instagram translate,
  reply, panel, Retry and hover originals are confirmed working in Chrome without it. Not changed yet.
- **R10, prompt encoding and a separate back-translation call:** no.
