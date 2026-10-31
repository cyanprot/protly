# Keyboard and app UI design (Sprint 9)

Date: 2026-10-30. Status: approved by Cyan in a brainstorm on 2026-10-30.
Inputs: `docs/research/2026-10-30-ui-audit.md` (issue IDs B*, K*, P*, F*, A*, H* below are from it) and
`docs/research/2026-10-30-competitors.md`.

## Goal

The keyboard works but does not feel finished. This campaign makes the moments people touch many times a message
feel good: the bar, the protly key, the wait for a result and the result itself. It also gives the container app
a first screen that gets a new user to a working Translate on the first try.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Keyboard first: bar, protly key, result. App second. Chrome extension not in scope. | The bar is seen dozens of times a message. |
| D2 | Keys, key sizes and the keyboard background stay Apple's (iOS 26 glass). Only protly's own parts get an accent: the center action, the protly key, the progress strip, the result card. | Blends into every host app; the CI layout checks against Apple stay valid. |
| D3 | Accent is the northprot brand, not a new color: a paper pill with ink text in dark mode, an ink pill with paper text in light mode (paper `#F5F0E6`, ink `#1A1F2E`, as in `src/ui/tokens.css.js`). A soft moving gradient glow is allowed only while a call runs. | Keeps one brand. The glow is the keyboard's single exception to the brand's no-gradient rule, and only while something is happening. |
| D4 | Results stream into a glass card while the keys stay usable until the first text arrives. | Lag is the top complaint about AI keyboards; the first words on screen make the wait feel short. |
| D5 | The app becomes one scrolling guide screen, not paged onboarding. | One screen people can come back to; less code than a paged flow. |
| D6 | No haptics, no settings, no VoiceOver work in this campaign. | Haptics and settings belong to the settings campaign (blocked on an xtool release after 1.24.0). VoiceOver (K2) is a separate small follow-up. |

## Part 1: bar and protly key (Sprint 001)

Files: `ios-app/Sources/ProtlyKeyboard/` (`ProtlyBar.swift`, `KeyboardViewController.swift`, `ProtlyLayout.swift`
as needed) and ProtlyCore for any logic that can be tested. CI, each in its own commit: `ios-app/CI/measure.py` if
the pill disturbs a measurement, and the four center-slot expectations in `ios-app/CI/UITests/PhoneChecksUITests.swift`
(`expectSlot(..., equals: "Translate")` and `equals: "Polish"`), which the new labels break. No other CI file and no
workflow change.

Order: the code work starts at once. Sprint 002 of the sim-phone-checks campaign owns the CI files while it flies and
also turns on Full Access in the simulator (`test0_access`). So the branch rebases on main after that sprint lands,
then edits the four expectations to match the label's words only, not the symbols, which OCR may not read:
8.5-1o (`ru:` draft) expects `Русский`, 8.5-6o expects `English`, 8.5-7o and 8.5-9o expect `Polish`. The OCR in
`ios-app/CI/UITests/Reader.swift` reads only `ko-KR` and `en-US`, so Part 1 may also add `ru-RU` to its recognition
languages (one more allowed CI line). Only then does it run `[shots]`. (8.5-9o, the Spanish flip, already passes on
main since typing-fixes Sprint 002 landed: runs d9a03f1-29 and e014ba8-38.)

- **Full-slot targets (B1, B8).** Each of the three slots is a button the full third of the width and the whole
  band above row 1 (`topBand` plus `toolbarHeight`, about 46 pt), not only the text row. Thin dividers between
  slots, like Apple's. Text sits where Apple's does (22 pt below the glass top); if that moves `topBand`, update
  `measure.py` to match.
- **Left slot, flip (B4).** Drawn in the primary color only when the other reading is a plausible word in that
  language (it is in that language's word list, `en_50k.txt` or `ko_50k.txt`); otherwise secondary (dimmed). The curly quotes are removed (in Apple's bar quotes mean "keep as typed",
  the opposite).
- **Center slot, action (B2, B3, B5).** A pill in the D3 colors with a symbol and the target:
  `✦ → English` (or the prefix's language, such as `→ Русский`), `✦ Polish`, `✦ 한 Polish` (`ko:` prefix),
  `⧉ Read` (clipboard), `↶ Undo`. The action stays visible while a word is typed. It appears with a short fade and
  scale (about 0.15 s).
- **Right slot.** Unchanged: one fix or completion.
- **Without Full Access (F1, keyboard side).** The pill is dimmed with a lock. A tap shows one line with the path
  (Settings > General > Keyboard > Keyboards > Protly > Allow Full Access) and Done, instead of a failed call.
- **Protly key (K1).** Same accent tint as the pill; its symbol follows the action it will run (`✦`, `⧉`, `↶`).
- **Pressed state.** Every slot and the protly key show a pressed state. No haptics (D6).

Done when: `swift test` passes; the last `[shots]` run (after the rebase above) publishes `STATUS measured`,
layout `RESULT PASS` (a single band off by +17 pt together with a top-edge range of 17 pt counts as the known CI
flake) and every phone check PASS; the tower reads the published accessibility trees and finds each slot's hit frame
at least 120 x 40 pt and the center label as specified; shot 06 (`hello ` typed) shows the pill. Empty-field shots
(02-05) keep an empty center slot (showing something there is B6, out of scope). If Full Access is off in a run,
the shots show the locked pill instead, which checks the F1 state.

## Part 2: app guide screen (Sprint 002)

Files: `ios-app/Sources/Protly/ProtlyApp.swift` only. The icon (`ios-app/Support/AppIcon.png`) stays.
The app does not link ProtlyCore and must keep building with `xtool dev build` on the laptop.

One scrolling screen in the D3 colors (paper background, ink text; reversed in dark mode). Titles in the system
monospaced design, echoing the extension's mono font without bundling a font file.

1. **Hero.** `protly` and one line: "Write Korean, send English."
2. **Turn on Protly (F2).** Two steps, each with a one-line reason, and an `Open Settings` button
   (`UIApplication.openSettingsURLString`, which opens Protly's own Settings page with its keyboard switch). The
   app cannot read whether Full Access is on (no App Group), so it shows no status.
3. **Try it (A1, A4).** The test field, moved up, with five chips. The flip and the suggestion come only from keys
   typed on the keyboard, so two chips ask the user to type; the others put text in the field. A tap focuses the
   field and shows one line:
   1. Type `dkssud`, then tap the left slot (field not changed).
   2. Type `teh`, then tap the right slot (field not changed).
   3. Inserts `ru: 고마워`, then: tap ✦.
   4. Inserts a short English sentence with mistakes, then: tap ✦ Polish.
   5. After a Replace: tap ↶ Undo (field not changed).
4. **About me (A2).** After `Copy for the keyboard`, focus the test field and show a numbered banner:
   tap ✦ Read, Allow Paste, Save. The clipboard handoff itself is unchanged.
5. **What Protly sends.** One paragraph: only when an action is tapped, the field text (or the clipboard text for
   Read) and the About me note go to the model API. Keystrokes are never sent; words the keyboard learns stay on
   this phone.

Done when: `npm test` (`tests/about-me.test.js` compares the About me constants) and `swift test` pass; `xtool dev build` passes on the laptop
(the tower runs it). Screenshots of this screen come in Sprint 003; until then the owner checks it on the phone.

## Part 3: streaming result card (Sprint 003)

Starts after Sprint 004 of the typing-fixes campaign lands (it shares `ios-app/CI/**` and the workflow).

**Flow.**
1. A tap on an action keeps the keys. The bar becomes a progress strip: the D3 glow moving across it, the mode and
   target ("Translating → English…") and `✕`. A second tap on the strip does nothing (B10). After 8 s a
   "Still working…" line appears (P5).
2. When the first text arrives, a glass card slides up from the bar over the keys, with a header naming the target
   (`→ English`), the result text arriving with a caret, and, once complete, the back translation dimmed below it
   (P1, P2).
3. Buttons, at least 44 pt: `Copy` and `Replace` for Translate and Polish; `Copy` and `Insert` for Read (P3, P8).
4. `✕` or Cancel puts the cursor back where it was (P6). If the field text changed during the call, the result is
   kept and only `Copy` is offered (P10).
5. Errors in plain words. Retry only where it can work: network, timeout, overloaded, rate limit (P4).
6. Card text follows Dynamic Type (P7).

**Streaming.**
- `ActionAPI.body` adds `"stream": true`; the JSON schema output and the other fields stay.
- A pure server-sent-events parser in ProtlyCore collects `content_block_delta` text deltas (thinking deltas are
  read and dropped) and yields the partial value of `"translation"` from the JSON being built (escapes, a `\u`
  escape cut across chunks, and multi-byte UTF-8 split across chunks are handled).
- `ActionAPI.parse(status:body:)` is split: the part that turns the model's text plus its stop reason into an
  `ActionResult` becomes its own function, used by both the whole-body path and the stream. The stop reason comes
  from `message_delta`: `end_turn` parses the JSON; `max_tokens` maps to `.truncated`; `refusal` to `.refused`.
  An `error` event maps through the same table as today's error bodies (`overloaded_error` to `.overloaded`, and
  so on).
- A reply that is not 200 is a plain JSON error body, not a stream: it is read bounded and mapped by today's
  `kind(status:body:)`.
- `collect` buffers the whole reply, so the stream gets its own bounded reader. `maxResponseBytes` (2 MB) counts the
  raw stream bytes, framing and thinking deltas included; the plan confirms 2 MB still covers a full 16000-token
  reply with SSE framing. The idle timeout and the total timeout keep their current values.
- `ActionClient.run` returns a stream of partial results followed by the final result or an error.

**CI.**
- A stub action client in the keyboard extension replays fixed chunks with delays. The extension cannot read the
  host's launch arguments, and the CI key may be empty, so the stub is chosen at compile time: a compilation
  condition (`PROTLY_CI_STUB`) set only on the `ProtlyCIKeyboard` target in `ios-app/CI/project.yml`, checked before
  the API key, keeping the stub out of the phone build. Full Access in CI comes from `test0_access`. Shots: waiting,
  mid-stream, complete, error, each in dark and light mode (P9).
- Light mode for the bar shots; a check that each bar slot's hit frame is at least 120 x 40 pt.
- Shots of the app guide screen (Part 2) in dark and light mode.
- Memory during a stream stays under the 40 MB budget.
- The `[probe]`-only panel probe in `PhoneChecksUITests.swift` waits for `Insert` / `Retry`; update it to the new
  button names (`Replace`, `Copy`, `Retry`).

Done when: `swift test` covers the SSE parser cases above and passes; `npm test` passes; the last `[shots]` run
publishes `STATUS measured`, layout `RESULT PASS` (flake rule as in Part 1), the new checks pass, and the card and
app shots exist in both modes.

## Out of scope (later candidates)

- Register chips on the result (casual / polite / formal; 반말 / 해요체 / 합쇼체).
- A Korean gloss under a Polish result.
- Streaming in the Chrome extension.
- VoiceOver labels and announcements (K2); haptics, sound and settings (H1, A3).

## Owner phone checks (added to the batch at the end)

The feel of the bar and the pill on the phone; a real streamed Translate and Polish; Open Settings landing on
Protly's page; the Try it chips.
