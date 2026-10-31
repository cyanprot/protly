# Keyboard and app UI design (Sprint 9)

Date: 2026-10-30. Status: approved by Cyan in a brainstorm on 2026-10-30.
Inputs: `docs/research/2026-10-30-ui-audit.md` (issue IDs B*, K*, P*, F*, A*, H* below are from it) and
`docs/research/2026-10-30-competitors.md`.

## Owner amendments 2026-10-30 (after the first phone build)

These override the text below wherever they disagree.

- **No sparkles.** Translate and Polish show words only in the pill (`→ English`, `Polish`); `BarAction.symbol` is
  nil for them. The protly key falls back to `character.bubble` (`BarAction.keySymbol`). The logo, the app icon
  and any brand mark are a later Recraft pass, so no placeholder art until then. Task 1.5: shot 06 shows `Polish`
  with no symbol in front.
- **Written for an English speaker, not Korean only.** Hero: "Polish and translate as you type." Try it has two
  chips, Polish first (the English sentence with mistakes, "Tap Polish in the bar.") and Translate Korean
  (`오늘 고마워`, "Tap → English in the bar."); the `ru:` chip is gone. Instruction rows: `teh`, then Undo, then
  "Writing Korean? Type `dkssud`: it turns into 안녕 on its own. The left slot flips a word back." (2026-10-31:
  replaced the earlier "Type `dkssud`, then tap the left slot.", because the bundled word lists turn `dkssud` into
  안녕 by themselves, so there is nothing to flip; phone check owed.) Other languages come gradually, in later plans.
- **Dictation follows the keycaps.** The keyboard reports `en-US` (Info.plist `PrimaryLanguage` and the
  `primaryLanguage` override), `ko-KR` only on Korean keycaps; before, dictation was Korean only. Phone check:
  dictation listens in English on English keycaps and in Korean on Korean keycaps.
- **Open, not in this campaign:** Read translates someone else's text into Korean (`ActionMode.in`). An English
  speaker needs English; changing the target is logic, planned later with the other languages.

## Tower decisions 2026-10-31 (review of #20, fixes from #22)

The owner delegated these to the tower. They override the text below wherever they disagree.

- **D4 deviation: the keys wait during the field read.** D4 keeps the keys live until the first text arrives. A key
  typed while the field read walks the cursor to the end would land mid-text and join the text sent, so the keys
  wait for the read (`ProtlyActionHandler`; a gesture's `.end` still passes); the network wait that follows keeps
  them live, as D4 says. The whole read is capped at 2 s (`FieldReadBudget`): a new cursor step starts only while its
  full 1 s settle wait still fits, so a step on its way always settles and Cancel's record stays exact. A read the
  cap stops leaves text after the cursor and ends like any cut-short read ("Could not read the whole text. Select
  all, then tap again.", with Retry); the keys come back. Phone check owed: whether 2 s feels OK.

## Goal

The keyboard works but does not feel finished. This campaign makes the moments people touch many times a message
feel good: the bar, the protly key, the wait for a result and the result itself. It also gives the container app
a first screen that gets a new user to a working Translate on the first try.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Keyboard first: bar, protly key, result. App second. Chrome extension not in scope. | The bar is seen dozens of times a message. |
| D2 | Keys, key sizes and the keyboard background stay Apple's (iOS 26 glass). Only protly's own parts get an accent: the center action, the protly key, the progress strip, the result card. | Blends into every host app; the CI layout checks against Apple stay valid. |
| D3 | Accent is the northprot brand, not a new color: a paper pill with ink text in dark mode, an ink pill with paper text in light mode (paper `#F5F0E6`, ink `#1A1F2E`, as in `src/ui/tokens.css.js`). A soft moving gradient glow is allowed only while a call runs. | Keeps one brand. The glow is the keyboard's single exception to the brand's no-gradient rule, and only while something is happening. Cost, accepted: a filled pill shown on nearly every keystroke is the loudest thing on the keyboard, louder than the return key; an accent seen all the time loses force. The phone check judges whether it is too loud. |
| D4 | Results stream into a glass card while the keys stay usable until the first text arrives. | Lag is the top complaint about AI keyboards; the first words on screen make the wait feel short. Cost, accepted: while the strip shows, the flip and suggestion slots are gone even though typing goes on, and any key typed during the wait downgrades the result to Copy only (P10). |
| D5 | The app becomes one scrolling guide screen, not paged onboarding. | One screen people can come back to; less code than a paged flow. |
| D6 | No haptics, no settings, no VoiceOver work in this campaign. One exception: the protly key gets an `accessibilityLabel` naming its action (one line; today VoiceOver reads "Keyboard Type - emojis"). | Haptics and settings belong to the settings campaign (blocked on an xtool release after 1.24.0). VoiceOver (K2) is a separate small follow-up. Reduce Motion is not VoiceOver work and is in scope (Parts 1 and 3). |

## Part 1: bar and protly key (Sprint 001)

Files: `ios-app/Sources/ProtlyKeyboard/` (`ProtlyBar.swift`, `KeyboardViewController.swift`, `ProtlyLayout.swift`
as needed) and ProtlyCore for any logic that can be tested. CI, each in its own commit: `ios-app/CI/measure.py` and
`test_measure.py` (the pill moves the measured center label), the four center-slot expectations in
`ios-app/CI/UITests/PhoneChecksUITests.swift` (`expectSlot(..., equals: "Translate")` and `equals: "Polish"`),
which the new labels break, and the same center-label comparisons in `ios-app/CI/UITests/NetworkChecks.swift`.
No other CI file and no workflow change.

Order: the code work starts at once. Sprint 002 of the sim-phone-checks campaign owns the CI files while it flies and
also turns on Full Access in the simulator (`test0_access`). So the branch merges main after that sprint lands (no rebase: the PR may be open),
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
- **Center slot, action (B2, B3, B5).** A pill in the D3 colors with an SF Symbol and the target:
  `sparkles` `→ English` (or the prefix's language, such as `→ Русский`), `sparkles` `Polish`, `sparkles` `한 Polish`
  (`ko:` prefix), `doc.on.clipboard` `Read` (clipboard), `arrow.uturn.backward` `Undo`. SF Symbols, not Unicode
  glyphs (`✦ ⧉ ↶` come from fallback fonts and sit on different baselines). The symbol, the arrow and the name are
  separate views, so a right-to-left name (العربية, עברית) cannot reorder them; one line, shrinking to 80% before it
  truncates (`Bahasa Indonesia`). The bar's text stops growing at Dynamic Type `xxLarge`. The action stays visible
  while a word is typed. The pill follows the same appearance as the keys (KeyboardKit's
  `keyboardContext.colorScheme`), never a separate read, so a dark keyboard in a light app never gets an ink pill on
  dark glass. Motion: the pill fades and scales in (about 0.15 s, ease-out) and fades out faster (about 0.1 s);
  a label change (Translate to Polish) only crossfades. Under Reduce Motion it only fades.
- **Right slot.** Unchanged: one fix or completion.
- **Without Full Access (F1, keyboard side).** The pill becomes an outlined capsule (1 pt rule, no fill) with
  label-colored text and `lock.fill`, not a dimmed fill (40% opacity on the ink pill is about 2.5:1 and the pill is
  still tappable). A tap shows one line that says why, with Done, instead of a failed call:
  "Translate, Polish and Read need Full Access: Settings > General > Keyboard > Keyboards > Protly > Allow Full Access".
- **Protly key (K1).** Same accent tint as the pill; its symbol follows the action it will run (`sparkles`,
  `doc.on.clipboard`, `arrow.uturn.backward`), and its `accessibilityLabel` names that action (D6 exception).
- **Pressed state.** Every slot shows Apple's pressed look: a rounded `systemFill` highlight behind the slot, not
  a dimmed label. The protly key keeps KeyboardKit's pressed key. No haptics (D6).

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
monospaced design, echoing the extension's mono font without bundling a font file. Contrast on paper: system
`.secondary` is 3.3:1 and fails, so secondary text and placeholders use ink at 70% or more (5.7:1); in dark mode
paper at 60% or more on ink (6.0:1). An app-wide tint of ink (paper in dark mode), so buttons are not system blue
on paper. Text fields get a visible 1 pt rule, since they lose the Form's grouped backgrounds. Symbols in hint
lines are the same SF Symbols the keyboard shows, embedded in the text.

1. **Hero.** `protly` and one line: "Write Korean, send English."
2. **Turn on Protly (F2).** Two steps, each with a one-line reason, and an `Open Settings` button
   (`UIApplication.openSettingsURLString`, which opens Protly's own Settings page with its keyboard switch). The
   app cannot read whether Full Access is on (no App Group), so it shows no status. **What Protly sends** sits here,
   right after the Full Access reason, because that is where iOS shows its warning: only when an action is tapped,
   the field text (or the clipboard text for Read) and the About me note go to the model API. Keystrokes are never
   sent; words the keyboard learns stay on this phone.
3. **Try it (A1, A4).** The test field, moved up. First one line: switch to Protly with the globe key under the
   keyboard (and back the same way); without it the field opens with Apple's keyboard and nothing below works.
   Then three chips that put text in the field (a tap focuses the field and shows one hint line), headline first:
   1. Inserts a short Korean line (`오늘 고마워`), then: tap `sparkles` → English.
   2. Inserts a short English sentence with mistakes, then: tap `sparkles` Polish.
   3. Inserts `ru: 고마워`, then: tap `sparkles` → Русский.
   The three things that come only from keys typed on the keyboard are numbered instruction rows, not buttons
   (a button that changes nothing reads as broken):
   1. Type `dkssud`, then tap the left slot.
   2. Type `teh`, then tap the right slot.
   3. After a Replace, tap `arrow.uturn.backward` Undo.
4. **About me (A2).** After `Copy for the keyboard`, focus the test field and show a numbered banner:
   tap `doc.on.clipboard` Read, Allow Paste, Save. The clipboard handoff itself is unchanged.

Done when: `npm test` (`tests/about-me.test.js` compares the About me constants) and `swift test` pass; `xtool dev build` passes on the laptop
(the tower runs it). Screenshots of this screen come in Sprint 003; until then the owner checks it on the phone.

## Part 3: streaming result card (Sprint 003)

Starts after Sprint 004 of the typing-fixes campaign lands (it shares `ios-app/CI/**` and the workflow).

**Flow.**
1. A tap on an action keeps the keys. The bar becomes a progress strip: the D3 glow, the mode and target
   ("Translating → English…") and an `xmark` button with a hit area of at least 44 x 44 pt. A second tap on the strip does
   nothing (B10). After 8 s a line naming the operation appears ("Still translating…", "Still polishing…",
   "Still reading…") (P5). The glow stays out of the text's path (a thin band along the strip's edge), because in
   dark mode a paper glow passing under near-white text keeps changing its contrast. It animates one gradient
   offset, with no blur, and the loop stops on done, cancel and `viewWillDisappear`. Under Reduce Motion the
   gradient is still.
2. When the first text arrives, a glass card grows down from the strip over the keys (the strip is above the
   keys; under Reduce Motion it crossfades), with a header naming the target (`→ English`), the result text
   arriving with a steady caret, and, once complete, the back translation dimmed below it (P1, P2). Glass is the system
   `glassEffect` on iOS 26 with `.regularMaterial` below it (the target is iOS 17); no hand-rolled blur. The keys
   were live until now, so the card's buttons appear under a typing thumb: they ignore taps for 0.5 s after
   the card appears, reusing the About me Save guard `AboutMe.canSave(shownAt:now:)`.
3. Buttons, at least 44 pt: `Copy` and `Replace` for Translate and Polish; `Copy` and `Insert` for Read (P3, P8).
4. `xmark` or Cancel puts the cursor back where it was (P6). If the field text changed during the call, the result is
   kept and only `Copy` is offered (P10).
5. Errors in plain words, each with its recovery step (one line per `ActionError.Kind`). Retry only where it can
   work: network, timeout, overloaded, rate limit (P4). Where an error shows depends on whether text has arrived:
   - **No text yet:** the error line replaces the strip's label, the keys stay, no card opens.
   - **Text on screen** (the reply was cut off, refused, or the connection dropped mid-stream): the text already
     shown stays, dimmed, with one error line under it and only `Copy` (plus Retry where it can work). Never wipe
     what the user has already seen.
6. Card text follows Dynamic Type (P7), capped at `accessibility2`; long text scrolls inside the card, the buttons
   stay pinned.

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
- One bar shot at a large text size (`xxLarge` or above) with a long target name, to catch label overflow.
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

The feel of the bar and the pill on the phone (is the pill too loud, D3); a real streamed Translate and Polish;
the card not catching a typing thumb; Open Settings landing on Protly's page; the Try it chips; a dark keyboard
field in a light app.
