# iOS Shortcut Implementation Plan

> **For Claude:** small plan; execute task by task, tests before commit.

**Goal:** Translate Instagram DMs in the native iPhone app with one Back Tap: incoming messages to Korean, a copied Korean draft to the friend's language, with the conversation on screen as context.

**Architecture:** An iOS Shortcut the user builds by hand calls the Claude Messages API directly (no prot, no VPN: the user will not keep Tailscale on the phone, it drains the battery). It sends a screenshot of the current screen plus a text block (memos, mode, draft). The request body is a fixed JSON template kept in the repo; the shortcut fills two slots. An eval script sends the same template from the laptop, so what the phone sends is what was tested.

**Tech Stack:** iOS Shortcuts, Claude Messages API (`claude-sonnet-5-5`, image input, `output_config.format`), Node 22 eval script, Chrome headless for a synthetic screenshot.

---

## Decisions

| Topic | Decision | Why |
|---|---|---|
| API path | Phone calls `api.anthropic.com` directly, key in a Text action | No VPN on the phone; Shortcuts is not a browser, so the org CORS block does not apply |
| Key | A separate key just for the phone, named `iphone-shortcut` | Revoke it alone if the phone or an iCloud shortcut copy leaks |
| Delivery | Step-by-step build guide, not a `.shortcut` file | iOS only imports signed shortcuts, signing needs macOS, there is no Mac. Third-party signing services would get the file |
| Trigger | Back Tap (double tap) runs the shortcut; it also runs from the Shortcuts app | Back Tap keeps Instagram in front, so Take Screenshot captures the DM |
| Mode | Decided in the shortcut, not by the model: clipboard contains Hangul = `out`, else `in` | Deterministic. After an `out` run the clipboard holds the translation, so the next run is `in` |
| Context | Screenshot of the screen, resized to width 720 px, JPEG | 720 x 1561 stays under the API's 1568 px long edge, so nothing is downscaled again; small upload |
| Incoming | Translate the friend's non-Korean messages visible on screen; no copy needed | Fewer taps than copy per message |
| Memos | One Text action listing people; the model matches the name at the top of the screenshot | No menu tap; a handful of memos is cheap |
| JSON safety | Static parts are pre-escaped in the template; the one dynamic text (memos + mode + draft) goes through 4 Replace Text actions: `\`, `"`, newline, tab | Shortcuts has no JSON-string-escape action; dictionary bodies cannot nest the `messages` array without dozens of taps |
| Output | `output_config.format` json_schema `{translation, back_translation}`; `out` copies translation and shows a notification with the back translation; `in` opens Quick Look | Schema avoids parse failures on the phone |
| Model | Sonnet 5.5, effort and thinking picked by the eval (latency vs quality) | Phone wait time matters more than on desktop |
| Scope | Instagram only. No Gmail, no cache, no history on the phone | YAGNI |

Rejected: a Safari Web Extension (needs Mac + Xcode + paid account, mobile web DMs differ from desktop); prot proxy (needs VPN); Orion browser with the Chrome extension (no native messaging, no CORS path).

## Task 1: Body template + escape model

**Files:**
- Create: `ios/body-template.json` (one line, slots `{{IMAGE_B64}}` and `{{TEXT}}`)
- Create: `ios/system-prompt.txt` (readable source of the system prompt)
- Create: `scripts/ios-body.mjs` (exports `escapeLikeShortcut(s)` that mirrors the 4 Replace Text actions in order, and `buildBody({image, text})` that fills the template)
- Test: `tests/ios.test.js`

Tests:
1. Template with slots filled by `escapeLikeShortcut` of a nasty string (quotes, backslashes, newlines, tab, emoji, Korean) parses with `JSON.parse` and round-trips the string exactly.
2. The template's embedded `system` equals `ios/system-prompt.txt` (so the readable source and the pasted template never drift).
3. Template carries `model`, `max_tokens`, `output_config.format` schema with `translation` and `back_translation` required.

System prompt rules, carried from the extension (`src/lib/prompts.js`): casual register, slang as natural equivalents, keep emoji/names/line breaks, writer is male (masculine forms), friend's gender from memo or screen else neutral, no added greetings or sign-offs, banmal Korean. Mode `in`: translate the friend's latest non-Korean messages on screen (the friend's bubbles are on the left, mine on the right), English and others go to Korean, skip Korean ones; back_translation empty. Mode `out`: translate DRAFT into the language the friend writes in on screen, else English; back_translation in Korean. Memo match: use the PEOPLE entry whose name matches the chat header, none if no match.

## Task 2: Eval against the live API

**Files:**
- Create: `scripts/fixtures/ios-dm.html` (synthetic DM screen, invented names and text, phone-sized)
- Create: `scripts/eval-ios.mjs`

Steps: render the fixture with `google-chrome --headless --screenshot --window-size=393,852 --force-device-scale-factor=3`, resize to 720 wide JPEG with Python PIL, base64, `buildBody`, POST with the key read from `~/.config/anthropic/api-key` (never printed). Cases: `in` with Russian + English bubbles; `out` with a Korean draft containing quotes and two lines; `out` where the friend writes English. Check: HTTP 200, JSON parses, language right, latency printed, input tokens printed. Compare effort low vs medium (thinking adaptive) and pick; write the result into this plan's notes.

## Task 3: Build guide

**Files:**
- Create: `docs/ios-shortcut.md` (action-by-action build list, Back Tap setup, the key step, the 3-message test, troubleshooting by error text)
- Publish the same guide as a private Artifact so the user can open it on the iPhone and copy the template and prompt from there. The Artifact and the repo hold no key and no real memo.

Phone test (user): (1) incoming Russian message, (2) Korean draft with a quote and a line break, (3) the API error path with a deliberately wrong key.

## Notes

Review (code-reviewer, APPROVE WITH CHANGES), applied:
- Parse the LAST content block (a thinking block can come first), check `type == error` and `stop_reason`, show both in an alert.
- Cut `escapeLikeShortcut` and its JS round-trip test: it modelled the user's typing, not the phone. Tests now check only the template (ASCII one line, each slot once, system prompt matches source, schema). The phone test with a nasty draft is the real check.
- Escape steps: backslash, quote, newline, then `[\x00-\x1F]` to a space (covers CR, tab, other controls). Slots filled with Replace Text regex OFF.
- Output prefixed `[in]` / `[out]` so a wrong mode from stale clipboard Korean is visible.
- Key in its own workspace with a spend limit; never share the shortcut.
- Hangul pattern written as `\uAC00`-style escapes so the copy block stays ASCII.
- Dropped the effort matrix: one template, Sonnet 5.5, adaptive thinking, effort low.

Eval 2026-10-28 (`scripts/eval-ios.mjs`, synthetic 720x1561 JPEG, 46 KB): 3/3 PASS.
- in: 2.8 s, 2395 input tokens; translated only the friend's 3 bubbles after my last one, skipped the earlier one.
- out with memo (reply in Russian): 1.6 s, Russian, quotes / backslash / tab / `$1` / emoji survived.
- out without memo: 2.2 s, English (the screen mixes English and Russian).
- No thinking block was returned at effort low.
- Workspace: the laptop key is org-level and needs `anthropic-workspace-id`; the eval adds it from `~/.config/anthropic/configs/default.json`. The phone key is made inside a workspace and needs no header.

Delivered: `docs/ios-shortcut.md` and a private Artifact copy with copy buttons (claude.ai/artifact/YAQtPrEhmbaUFbreaX6RrC). Open: the user's phone test (iPhone 13 Pro, 1170x2532 screenshot -> 720x1558).
