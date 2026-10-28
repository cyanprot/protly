# protly: rename, redesign, any-site input (design)

Date: 2026-10-28. Status: approved by the user in chat; revised after spec review the same day.

## Goal

1. Rename the project from ig-translate to **protly**, everywhere.
2. Give the Chrome extension a real look, built on the northprot brand, plus a few UX gains.
3. Make it usable in any site's text box, not only Instagram and Gmail.

Out of scope: iOS Shortcut features and rebuilding/reinstalling the Shortcut on the phone (on hold, too many blockers);
per-site adapters for other chat sites (Discord, WhatsApp, ...); intercepting Enter outside Instagram; bundling the
Instagram and Gmail content scripts.

## Decisions taken with the user

| Question | Choice |
|---|---|
| Visual direction | northprot brand (`~/Document/northprot-brand-assets/BRAND.md`) |
| Accent color | none: ink + paper only, red for errors only |
| Surfaces | popup, options page, Instagram in-page UI, Gmail in-page UI |
| UX extras | shared preview card with key hints; popup as control center; options auto-save and diagnostics; usage and cost display |
| Any-site approach | A: keyboard command plus context menu, script injected on demand |
| Any-site code loading | esbuild bundle `dist/generic.js` with fonts inlined; nothing exposed to arbitrary sites |
| Rename scope | everything |

Deliberate brand departure: BRAND.md 5.3 sanctions only the `n` glyph as a single-letter mark. protly is a product,
not the northprot mark, so it gets its own `p` glyph built the same way. The wordmark rules (lowercase, JetBrains Mono
Medium, ink/paper only, no ornaments) still apply to `protly`.

## 1. Rename (its own sprint, with its own exit check, before any UI work)

Chrome derives an unpacked extension's ID from its folder path. Moving the folder changes the ID, which orphans
`chrome.storage.local` (thread memos, settings, cache: 32K in
`~/.config/google-chrome/Profile 1/Local Extension Settings/dcfndjmllblfabckkelnflfmnkdochai/`) and breaks the native
host's `allowed_origins`. Removing an extension deletes its storage folder, so the order below matters.

1. **Back up first.** Copy `dcfndjmllblfabckkelnflfmnkdochai/` to `~/.config/protly/storage-backup-dcfndjml/`,
   outside the Chrome profile.
2. Generate an RSA key pair; the public key goes in `manifest.json` as `key`, the private key stays out of the repo at
   `~/.config/protly/extension-key.pem`. The ID (X) is now fixed by the key, not the path.
3. Rename inside the code: CSS prefix `igt-` to `pl-` (including `data-igt-hide`), log prefix `[igt]` to `[protly]`,
   `host/ig_translate_host.py` to `host/protly_host.py`, the host name in `src/lib/native.js` and `host/install.sh`,
   `package.json` name, manifest `name`/`default_title`, every user-visible `ig-translate:` string, the iOS cherri
   source and docs (`Protly`). Historical plan docs and `.claude/campaigns/` stay untouched. `npm test` green.
4. Fully quit Chrome (`pkill -x chrome`, confirm no process). Move `~/projects/ig-translate` to `~/projects/protly`.
   Copy the LevelDB folder to `Local Extension Settings/X/`.
5. `host/install.sh X` writes `com.northprot.protly.json`; delete `com.northprot.ig_translate.json`.
6. Move the handoff baton `~/.claude/handoffs/-home-cyan-projects-ig-translate.md` to the protly slug.
7. **User step A:** start Chrome, chrome://extensions, Load unpacked `~/projects/protly`. Leave the old (broken) entry
   in place for now. Claude does not edit Chrome's signed Secure Preferences.
8. **Exit check:** the loaded ID equals X, an Instagram thread memo is present, a translation goes through the host.
9. **User step B:** only after the exit check passes, remove the old entry. If the check fails, restore from the
   backup in step 1 (Chrome quit, copy into `X/`).

## 2. Design system (`src/ui/`)

- `tokens.css`: `--pl-paper #F5F0E6`, `--pl-ink #1A1F2E`, `--pl-muted` (ink at 60%), `--pl-rule` (ink at 15%),
  `--pl-err` (red, AA contrast on both themes). `[data-pl-theme=dark]` swaps paper and ink. No shadows, no
  gradients; elevation is a 1px rule.
- Fonts: JetBrains Mono Regular and Medium, Latin subset woff2 built with fonttools from the system OTFs
  (`/usr/share/fonts/jetbrains-mono-fonts/`), family name `protly-mono`. Registered at runtime with
  `document.fonts.add(new FontFace(...))` (Chrome ignores `@font-face` inside shadow roots; a document-level
  FontFace is visible to them). Source: `chrome.runtime.getURL` on Instagram and Gmail (fonts added to their
  existing web-accessible entries), inlined bytes in `dist/generic.js`. `src/ui/fonts.js` takes the source as an
  argument so both paths share it. Translated message text keeps the site's font; only protly's own UI uses the mono.
- `theme.js`: reads the page's effective background color, picks light or dark by luminance, re-checks on a
  MutationObserver of `html`/`body` class and style attributes. Popup and options use `prefers-color-scheme`.
- Components, each in its own shadow root so site CSS cannot reach them:
  - **Preview card**: states working (animated dots), preview (Korean back-translation, model label, language chip,
    action buttons, key hints), error (red text, preview controls kept when a preview exists). Key hints:
    Instagram `Enter send · Esc undo · Alt+Enter Opus`; Gmail and generic `Esc undo` plus Opus/Undo buttons.
  - **Toast**: replaces `showBanner` (same dedupe and transient semantics).
  - **Instagram FAB + panel**: a square `p` tile (1px rule, small radius) opening the thread settings as a card.
- `src/ui/errors.js`: one table of user-facing messages per API error kind, replacing `ERROR_BANNERS`
  (`src/content/main.js`) and `ERRORS` (`src/content/gmail/compose.js`), used by all three surfaces.
- Icon: a `p` glyph outlined from JetBrains Mono Medium on a paper square, same recipe as the northprot favicon `n`
  (`~/Document/northprot-brand-assets/src/build_svg.py`); PNGs at 16/32/48/128. The `protly` wordmark is an
  outlined SVG used in the popup and options headers.
- The new `src/ui/*` modules join the Instagram and Gmail web-accessible entries (their loaders `import()` them).

The existing logic (`preview.js` reducer, `outgoing.js`, `gmail/compose.js`) keeps its behavior; rendering moves to
the components.

## 3. Popup as control center

- Wordmark header.
- Toggles: "Polish English on Enter (Instagram)" (existing `polish` key; see the polish rule in 6), Instagram, Gmail
  (new `sites` key, `{instagram: true, gmail: true}` by default; a content script whose site is off mounts nothing,
  and Alt+T there falls through to the generic path).
- Current tab: "Instagram: active", "Gmail: active", "site off", "Alt+T ready" (any other page), "unavailable here"
  (chrome://, Web Store), or a problem with its reason. The `badge` message gains a `reason` field; the background
  keeps it per tab in `chrome.storage.session` and clears it on `tabs.onUpdated` (status `loading`) and
  `tabs.onRemoved`.
- Usage: today and this month, in US$, from section 4.
- Link to the options page.

## 4. Usage and cost

The native host passes the API response through unchanged, so every 2xx body carries `usage` and `model`.

- Hook: `callClaude`'s 2xx return, so a response later re-requested by `callJson` after a parse failure is still
  counted (it was billed).
- Record: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` (split into
  `ephemeral_5m`/`ephemeral_1h` when the response gives the breakdown, else counted as 5m) into
  `usage[YYYY-MM-DD][body.model]` in `chrome.storage.local`.
- Writes are serialized through one promise chain in the service worker so concurrent calls do not lose increments.
- Price: one table per model id, per million tokens: input, output, cache read, cache write 5m, cache write 1h.
  Values are checked against the Anthropic pricing page when the plan is written. Unknown model: tokens recorded,
  cost shown as "?".
- Days older than 62 are pruned on write.

## 5. Options page

- Saves each field on change; the Save button goes away. A short "saved" mark confirms.
- Diagnostics panel:
  - Host: a new request shape `{id, ping: true}` (no `body`). The host answers locally, without calling the API, with
    `{id, ping: {ok, key_present, workspace_header}}`, never the key itself. `native.js` gains a `ping()` that
    resolves this shape; the existing `{status, body}` path is unchanged. Host tests cover it.
  - "Test call": a minimal request through the normal path, showing model and round-trip time.

## 6. Any-site text box

**Loading.** `npm run build` (esbuild, new dev dependency) bundles `src/generic/run.js` and its imports from
`src/lib/` and `src/ui/` into `dist/generic.js` (IIFE), with the woff2 fonts inlined. The background injects it with
`chrome.scripting.executeScript({files: ['dist/generic.js']})`. No resource is web-accessible to arbitrary sites, so
the fixed ID cannot be probed from them. `dist/` is gitignored; `npm test` runs the build first so a stale or missing
bundle fails loudly.

**Permissions.** `activeTab`, `scripting`, `contextMenus`; `commands` entry `run`, suggested key `Alt+T`. A command or
a context-menu click grants activeTab for that tab.

**Frame.** Context menu: inject into `info.frameId`. Command (no frameId): inject into the main frame; `run.js`
follows `document.activeElement` into same-origin `iframe.contentDocument`s. Cross-origin iframes are out of reach.

**Routing.** On the command the background sends `{type: 'command'}` to the tab. An adapter answers `handled` when its
own composer is focused:
- Instagram composer: idle state starts a translate (Hangul) or a polish (other letters), like Enter but without
  sending; a translating or preview state ignores it (Enter sends, Esc undoes). A new reducer event `run` carries
  this, so `enter` is untouched.
- Gmail compose body: the existing Translate action. Gmail's in-page Alt+T keydown listener is removed (a command
  shortcut never reaches the page) and the button stays.
No answer (no content script, site off, or focus elsewhere): inject `dist/generic.js`.

**Polish rule (one rule everywhere).** Explicit invocation (Alt+T, the Gmail button, the context menu) always
translates or polishes. The `polish` toggle only governs the automatic polish on Enter in the Instagram composer.
`compose.js`'s `flags.polish` gate is removed.

**Korean IME.** A command carries no composition state, and the message arrives after a background round trip.
- Adapters track `compositionstart`/`compositionend` on their composer and, on `command`, wait for `compositionend`
  (up to 500 ms) before reading.
- `run.js` is injected after the fact and cannot have seen `compositionstart`, so it commits any open composition by
  blurring and refocusing the element (restoring the caret), waits one animation frame, then reads.
- Never write into a box while a composition is active.

**Behavior of `run.js`.**
- Focus in a textarea, text input or contenteditable:
  - A language prefix (`ru: ...`, parsed by `parseLangPrefix`) translates the rest into that language, whatever its
    script.
  - Else Hangul translates to English.
  - Else letters are polished.
  - The result replaces the box text (textarea/input: `setRangeText` plus an `input` event; contenteditable: select
    all and `execCommand('insertText')`, the path the Instagram writer uses). A preview card anchored to the box shows
    the back-translation, language chip, Opus and Undo; Esc undoes. A failed write restores the original and says
    nothing was changed.
- A selection outside any box: translated to Korean with `otherTarget: 'ko'` passed explicitly, shown in a popover
  card anchored to the selection. A selection that is already Korean gets the toast "Already Korean."
- Nothing usable: the toast "Put the cursor in a text box or select text."

**Context menu.** "protly: translate selection" (selection context), "protly: translate or polish this box"
(editable context). Same behavior as above.

**Prompts.** The outgoing prompt is framed as a DM to a friend. The generic path adds one line saying the text is for
a text box on `<hostname>` and to keep the register the writer used, so forms and forums do not come out chatty.
Incoming translation uses the existing incoming prompt with no thread context and no memo.

**Limits.** Enter is never intercepted. Pages where injection is refused get the `!` badge with reason
"unavailable here".

**Pinned details (from the spec review).**
- Component CSS: `tokens.css` and component styles are JS string modules (`src/ui/*.css.js`), which work unbundled
  on Instagram/Gmail and inside the bundle. Popup and options `<link>` a plain `tokens.css` generated from the same
  source. Nothing is fetched from a page context on the generic path.
- Re-injection: `dist/generic.js` sets a `globalThis.__protly` flag in the isolated world on first run; later
  injections call into the live instance (one Esc listener, one card, fonts added once). Alt+T while a generic
  preview is open re-runs on Opus (same as the Opus button).
- The context menu goes through the same adapter-first routing as the command, so the Instagram composer is never
  bypassed. An injection rejected in a cross-origin frame maps to the "unavailable here" badge reason and a toast.
- Adapter IME: the `compositionend` wait applies only while a composition is active (otherwise read at once); on the
  500 ms timeout the adapter commits with the same blur/refocus as `run.js`.
- Generic incoming uses a new stateless background handler (like `email` and `polish`), never the thread-keyed
  `incoming` handler: no `c:` cache entries, no `partnerLang` writes.
- Badge reason is also cleared when a content script sends `badge` with `text: ''` (SPA navigation may not fire
  `tabs.onUpdated` loading).
- The generic prompt line sends the page hostname to the API. Intended.
- Usage fields: `usage.cache_creation.ephemeral_5m_input_tokens` and `usage.cache_creation.ephemeral_1h_input_tokens`.

## Errors

Every failure surfaces in the card or a toast with a plain reason from `src/ui/errors.js`. Host missing or
misconfigured: the card says so and points to the options diagnostics.

## Testing

- Unit (node test runner, jsdom where DOM is needed): theme luminance pick; usage aggregation, serialization, pruning
  and pricing (unknown model); host `ping` (Python tests); generic writer for textarea and input, and for
  contenteditable with `execCommand` stubbed as the existing `dom.js` tests do; prefix / Hangul / polish decision;
  command routing (adapter handled vs inject); reducer `run` event; site-off gating; toast dedupe; badge reason
  clearing.
- `npm test` (build included) before every commit. The repo stays local and is never pushed.
- Live check by the user. Claude never presses Enter or Send in any composer.

## Order

1. Rename (own sprint, exit check in section 1).
2. Design system applied to the existing Instagram and Gmail UI, with the shared error table.
3. Popup, usage, options (sections 3, 4, 5).
4. Any-site text box (section 6), including the Alt+T routing changes in the Instagram and Gmail adapters.
