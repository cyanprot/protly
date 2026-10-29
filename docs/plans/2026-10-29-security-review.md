# Security Review and Test Hardening Implementation Plan

> **For Claude:** cloud campaign. Planes implement one sprint each from a pasted brief; the tower verifies and lands.

**Goal:** Find the weak points in protly's own code (Chrome extension, native host, iPhone keyboard, ProtlyCore),
fix them, and leave tests that would have caught each one.

**Architecture:** Two planes, one per surface, with disjoint files so they fly together. Each plane audits its
surface with the review agents, fixes every finding it rates MEDIUM or worse with a failing test first, then fills
the test gaps the audit exposes. Findings that need a design decision go in the report, not in the code.

**Tech Stack:** Chrome MV3 extension (plain ES modules, `node --test`), Python 3 native messaging host
(`unittest`), Swift 6 toolchain in Swift 5 mode (ProtlyCore package tests run on Linux; the keyboard target needs
the iOS SDK and is compiled by the tower).

**Source of truth:** this file for the security campaign. `docs/plans/2026-10-28-ios-keyboard.md` stays the plan
of record for keyboard features; `docs/plans/2026-10-29-keyboard-visual.md` for the keyboard layout campaign that is
flying at the same time.

---

## Background the planes need

- Threat model, in order of weight:
  1. Untrusted page content. Instagram and Gmail pages (and any page the generic writer runs on) are hostile:
     their DOM, the text the user selects, and model output that echoes that text must never become markup,
     script, extension messages with authority, or native host commands.
  2. The Anthropic API key. Extension side: the key lives only in the native host (`host/protly_host.py`), which
     reads it from the user's config and calls the API; the extension never sees it. Keyboard side: the key is
     compiled into the keyboard from `ios-app/Sources/ProtlyKeyboard/Secrets.swift` (gitignored, written by
     `ios-app/scripts/make-secrets.sh`; CI and cloud use `enum Secrets { static let apiKey = "" }`). The user chose
     direct API calls from the phone (no VPN, no proxy). Embedding is accepted; check the key never reaches logs,
     error text, the UI, the pasteboard, or any request other than the API call. Report mitigations (spend limit,
     a dedicated key) as questions, do not redesign.
  3. Clipboard and field text on the phone: read only on the user's tap, sent only to the API, never kept on
     disk or logged.
  4. Robustness: malformed or hostile API responses, native messages, oversized input, and unexpected Unicode
     must not crash, hang, or corrupt the user's text.
- Every fix keeps current behaviour for valid input. `npm test` and `swift test --package-path ios-app/ProtlyCore`
  are green on `main` today (290 and 49 tests).
- Out of bounds for both planes: `ios-app/Vendor/**`, `ios-app/Package.swift`, `ios-app/xtool.yml`,
  `ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift`, `ProtlyBar.swift`, `ProtlyHeight.swift`, `.github/**`,
  `ios-app/CI/**` (the layout campaign owns these), `.claude/**`. Never print `Secrets.swift` or any key file;
  exclude `Secrets.swift` from every search.

## Sprint 001: Chrome extension and native host

**Files:** `src/**`, `host/**`, `tests/**`, `manifest.json`, `popup/**`, `options/**`, `scripts/build.mjs`

### Task 1: audit

1. Run `silent-failure-hunter` and `code-reviewer` over `src/`, `host/`, `manifest.json`, `popup/`, `options/`
   with the threat model above. Check at least: every `innerHTML`/template insertion and every place model output
   or page text reaches the DOM; `chrome.runtime.onMessage` handlers (sender checks, message shape checks, what a
   content script or page can make the background do); native messaging framing and size limits in
   `host/protly_host.py` and `src/lib/native.js`; error paths that could leak the key or full request bodies;
   `manifest.json` permissions, content script matches and `web_accessible_resources` (pages can import all of
   `src/lib/*.js` and `src/ui/*.js` today; narrow anything unused).
2. Write the findings list into the PR body as a table: id, severity, file:line, one-line description, fixed
   (commit) or reported.

### Task 2: fix

1. For each CRITICAL, HIGH and MEDIUM finding: a test that fails on `main`, then the fix, then the test passes.
   One commit per finding, message `fix(security): <id> <summary>`.
2. LOW findings: fix when the fix is a few lines and testable; otherwise report.

### Task 3: harden tests

1. Run `test-strategist` on the surface. Add tests for what it finds untested on the threat paths: hostile page
   text (markup, script-looking strings, very long input, RTL and zero-width characters), malformed native
   messages and API responses, message handlers called by an unexpected sender.
2. Keep tests offline and fast; no new dependencies.

**Sprint 001 done when:** every finding has a row, every CRITICAL/HIGH/MEDIUM row has a fix commit and a test,
`npm test` passes, and the extension still builds (`npm test` runs the build).

## Sprint 002: iPhone keyboard and ProtlyCore

**Files:** `ios-app/ProtlyCore/**`, `ios-app/Sources/Protly/**`, `ios-app/scripts/**`, and in
`ios-app/Sources/ProtlyKeyboard/`: `ActionClient.swift`, `FieldText.swift`, `Panel.swift`,
`ProtlyActionHandler.swift`, `KeyboardViewController.swift` (action, clipboard and field-reading code only; its
view lifecycle and `ProtlyRoot` belong to the layout campaign), plus `docs/security-review-ios.md` (new file)

### Task 1: audit

1. Install a Swift 6 toolchain for Linux (swiftly or the swift.org tarball) so `swift test --package-path
   ios-app/ProtlyCore` runs. If it cannot be installed, report BLOCKED before changing Swift code.
2. Run `silent-failure-hunter` and `code-reviewer` over the files above with the threat model. Check at least:
   where `Secrets.apiKey` flows (only into the request header), what errors show the user (no key, no raw
   response bodies with request echoes), response parsing in `ActionAPI` (missing fields, wrong types, huge
   bodies, non-UTF-8), timeouts and cancellation in `ActionClient`, pasteboard reads (only on tap, never stored),
   `FieldText` reading loops (termination, size), Hangul and `TypingSession` handling of unexpected scalars (no
   traps on index math, no unbounded growth), `make-secrets.sh` (file mode, no echo of the key, safe quoting).
3. Findings table in the PR body as in Sprint 001.

### Task 2: fix

1. As Sprint 001 Task 2. Logic fixes go in ProtlyCore with package tests. Keyboard-target fixes that cannot be
   compiled here stay small, and the PR body lists each one so the tower compiles and checks it on the phone. `Resources/keyboard-prompt.txt` is a copy of
   `ios/keyboard-prompt.txt` checked by `tests/ios-app.test.js`: edit neither, report prompt findings as questions.

### Task 3: harden tests

1. `test-strategist` on ProtlyCore. Add tests for hostile API responses, oversized and odd Unicode input to the
   detector, Hangul composer and `TypingSession`, and `ActionAPI` request building (the key only in the header,
   prompt text escaped by JSON encoding).
2. Write `docs/security-review-ios.md`: findings, what changed, and what
   the tower must check on the phone.

**Sprint 002 done when:** every finding has a row, every CRITICAL/HIGH/MEDIUM row has a fix and a test (or, for
keyboard-target code, a listed tower check), `swift test --package-path ios-app/ProtlyCore` and `npm test` pass.
