# protly iOS keyboard notes

Findings recorded while building the keyboard. Each sprint appends its own section.

## Sprint 1: detector

Measured 2026-10-28 with `swift run -c release --package-path ios-app/ProtlyCore protly-eval ios-app/ProtlyCore/Corpus`
(Swift 6.4.1, Linux). Word lists: FrequencyWords 2018 `en_50k` / `ko_50k`. Corpus: `Corpus/chat.txt` (25 lines,
written for this project), `Corpus/tatoeba-kor.txt` (1,993 lines, every 8th Korean sentence),
`Corpus/tatoeba-eng.txt` (2,266 lines, every 900th English sentence), sampled by `scripts/make-corpus.sh`.
The tatoeba files are monolingual, so code-switch accuracy rests on `chat.txt` alone, and its English figure
is on only 14 words.

On 2026-10-28, after the Sprint 1 review, `chat.txt` gained 5 lines (30 now) of glued chat shorthand that the
detector is known to get wrong (`ㅋㅋ진짜 웃겨`, `ㅇㅋ알겠어`, `ㄱㅅ`, `ㅎㅇ`, `ㅠㅠ나도 가고싶다`), so the gap is
measured. They are Sprint 3 work. Chat korean was 98.33% (60 words, 21.7% switching, at every prior bonus)
before them; the table below is after. The tatoeba numbers did not change, and the review's code fixes left
every figure identical.

"Switch" = words whose shown language changes at least once while the keys are typed one by one.

### Accuracy by prior bonus

| priorBonus | File | Language | Words | Accuracy | Words that switch while typing |
|---|---|---|---|---|---|
| 0.0 | chat | korean | 67 | 91.04% | 26.9% |
| 0.0 | chat | english | 14 | 92.86% | 42.9% |
| 0.0 | tatoeba-eng | english | 16544 | 99.35% | 1.1% |
| 0.0 | tatoeba-kor | korean | 8626 | 99.59% | 1.0% |
| 0.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| 1.0 | chat | korean | 67 | 91.04% | 26.9% |
| 1.0 | chat | english | 14 | 100.00% | 35.7% |
| 1.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 1.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 1.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| **2.0** | chat | korean | 67 | **91.04%** | 26.9% |
| **2.0** | chat | english | 14 | **100.00%** | 35.7% |
| **2.0** | tatoeba-eng | english | 16544 | **99.55%** | 0.8% |
| **2.0** | tatoeba-kor | korean | 8626 | **99.83%** | 0.5% |
| **2.0** | tatoeba-kor | english | 5 | **100.00%** | 40.0% |
| 3.0 | chat | korean | 67 | 91.04% | 26.9% |
| 3.0 | chat | english | 14 | 100.00% | 35.7% |
| 3.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 3.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 3.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| 4.0 | chat | korean | 67 | 91.04% | 26.9% |
| 4.0 | chat | english | 14 | 100.00% | 35.7% |
| 4.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 4.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 4.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |

From 1.0 upward the accuracy is flat; only the order of tied error words changes between runs (dictionary
iteration order).

### Top error words

- priorBonus 0.0: Korean 해x19 꽤x6 새x4 걔x4 뜰x1 도x1 (tatoeba-kor), 걔x1 (chat); English Zirix44 sox31
  Rimax16 (tatoeba-eng), sox1 (chat). Without a prior, 해 (`go`) and "so" (ㄴㅐ = 내) lose to the other list.
- priorBonus 2.0: Korean 꽤x6 걔x4 새x4 뜰x1 (tatoeba-kor), 걔x1 plus the six gap words ㅋㅋ진짜 ㅇㅋ알겠어
  ㄱㅅ ㅎㅇ ㅠㅠ나도 (chat; see the carry-over list below); English Zirix44 Rimax16 glaivex1
  diddlesx1 vibratedx1 Sorosx1 clarifiesx1 Skruax1 (tatoeba-eng). The English errors are names and rare words
  missing from `en_50k` that happen to compose into valid Hangul; the Korean errors are short syllables whose keys
  also spell an English list word (꽤 = keys `Rho` -> "rho", 걔 = `rO` -> "ro", 새 = `to` -> "to",
  뜰 = `Emf` -> "emf").

Chat switching is high by nature: those are the words where the user changes language, and they settle within
1-3 keys (one key cannot tell "r" from ㄱ). `FLIPS=1` before the command prints each switching word with its
per-key trace.

### Decision

**priorBonus 2.0** (the `LanguageDetector` default). It clears the Sprint 1 contract: tatoeba-kor 99.83%
(>= 99.5%), tatoeba-eng 99.55% (>= 99.3%), chat korean 98.33% (>= 98%) on the original 25 chat lines. The
91.04% after the gap lines is the known shorthand gap, not a regression.

## Carry into the Sprint 3 re-plan

Verified findings from the Sprint 1 review, left open on purpose:

- **Important: glued chat shorthand fails Hangul validity and becomes English gibberish.** ㅋㅋ진짜 -> "zzwlsWk",
  ㅋㅋㅋ그래 -> "zzzrmfo", ㅠㅠ나도 -> "bbskeh", ㅇㅋ알겠어 -> "dzdkfrpTdj", 아ㅋㅋ진짜 -> "dkzzwlsWk". Fix: allow
  leading and interior runs of lone consonants and face vowels between syllables. Re-run the eval after,
  because consonant-only English words (see, free, test, we) depend on the current rule.
- **Important: two-consonant chat abbreviations lose to English 2-letter entries.** ㄱㅅ -> "rt", ㅎㅇ -> "gd"
  (verified); likely also ㅈㅅ "wt", ㄱㄷ "re", ㄹㅇ "fd". Fix: a curated chat-abbreviation list checked before
  the frequency lookup. A blanket all-consonant rule would break see/red/free.
- **Medium: `LanguageDetector.bundled()` costs 136 ms (release, laptop)**, worse on an iPhone cold start. Do not
  load it on the main thread in `viewDidLoad`. Load lazily in the background with a "Hangul-valid -> Korean"
  fallback until it is ready, or ship pre-encoded, pre-sorted lists.
- **Medium: mixed tokens (nice하더라, playlist에) cannot come out of a per-word decision.** Decide in the re-plan
  whether to support a mid-word switch or accept the loss.
- **Medium (Task 2.4 review): KeyboardKit overrides Info.plist `PrimaryLanguage` ko-KR.**
  `KeyboardInputViewController+Setup.swift:54` sets `primaryLanguage` from `keyboardContext.locale`, which defaults to
  `Locale.current` (en_US on this phone). 9.9.1 ships no `ko.lproj`, so with a Korean locale `KKL10n` returns ""
  and the space, return and 123 keys lose their labels. Fix: set `state.keyboardContext.locale` explicitly and
  add a `ko.lproj/Localizable.strings` patch (listed in VENDORED.md) or supply our own key labels.
- **Minor (Task 2.4 review): the spike `SpikeBar` captures the text proxy at view build time and inserts outside
  KeyboardKit's action handler**, so KeyboardKit context (auto-capitalization) does not see the insert. The AI bar
  must insert through `controller.services.actionHandler.handle(...)` or read `controller.textDocumentProxy` at tap time.
- **Measured:** both lists add about 11 MB RSS. `decide(complete: false)` took about 58 us on a 1-key prefix
  and about 3 us on a longer one while it scanned up to 5,000 prefix matches; with `WordList.hasPrefix` (one
  binary search) it is about 1.1-1.5 us on a 1-key prefix and 3-5 us on 4-5 keys (release, laptop, 2026-10-28).

## Sprint 2: bare spike

Tested 2026-10-28 on the iPhone 13 Pro (iOS system language English), build 274b2e4 installed with
`xtool dev run` (free Apple ID team HAFRPRP47A). Signing worked first time: no zsign "free space of LoadCommands"
error, `-Xlinker -ObjC` not needed, the `-u _OBJC_CLASS_$_KeyboardViewController` flag keeps the principal class.

| # | Check | Result |
|---|---|---|
| 1 | Protly listed under Add New Keyboard, Allow Full Access | Yes |
| 2 | `안녕` button inserts 안녕 (ProtlyCore runs in the extension) | Yes |
| 3 | `API` round trip from the keyboard | HTTP 200, 1400-1700 ms (claude-sonnet-5-5, max_tokens 20) |
| 4 | `Marked` in Instagram DM, KakaoTalk, Messages | Underline visible while composing; 안녕 stays after unmark |
| 5 | `Context` before-count vs real draft length (3 paragraphs) | Same: full context, no truncation seen |
| 6 | `Clipboard` | Allow Paste prompt appears, count correct, prompt appears EVERY time |
| 7 | `Next` with only Protly + Emoji | Goes to Emoji; Emoji's ABC returns to Protly |
| 8 | Remove both Apple keyboards, keep Protly + Emoji | Possible (user removed them; then no way to type with the spike) |
| 9 | Crash or fallback to Apple's keyboard | None |

Consequences for the re-plan:
- Marked text works in all three target apps, so composing Hangul can use `setMarkedText` like Apple's keyboard.
- Full `documentContextBeforeInput` is available: Polish/Translate can read the whole draft.
- Clipboard read prompts on every access: read only on an explicit tap, never on keyboard appear (Sprint 5).
- API latency about 1.5 s for a tiny reply: Translate/Polish needs a visible in-progress state and streaming (Sprint 4).
- Until the real layout lands, keep an Apple keyboard installed while testing; the spike cannot type letters.

## Sprint 2: KeyboardKit

Tested 2026-10-28 23:25 on the iPhone 13 Pro, build 6fd4eea (KeyboardKit 9.9.1 vendored, review follow-up d0e788b),
Instagram DM, portrait, dark mode. Spec review PASS, quality review APPROVED_WITH_NITS.

| # | Check | Result |
|---|---|---|
| 1 | Loads; keys type, callouts, backspace repeat, space long-press cursor | Works. Space-drag cursor stutters (steps), Apple's glides continuously |
| 2 | Screenshot comparison vs Apple's English keyboard | Measured below |
| 3 | Crash or fallback to Apple's keyboard | None reported |

Screenshot measurements (1170x2532 px, 3 px per pt, 390 pt wide screen):

| | Apple | Protly (KeyboardKit) | Delta |
|---|---|---|---|
| Container top (from screen top) | 517 pt | 481 pt | Protly 36 pt taller |
| Toolbar / predictive bar band | 51 pt | 69 pt | +18 pt |
| Letter key height | 43 pt | 47 pt | +4 pt |
| Row pitch | 54 pt | 56 pt | +2 pt (rows +8 pt total) |
| Last row bottom to screen bottom (globe/mic band) | 71 pt | 79 pt | +8 pt |
| Key width / gap | about 25 / 5 pt | about 26 / 5 pt | close |

Visual differences besides size:
- Keycaps show UPPERCASE with shift active on an empty Instagram field; Apple shows lowercase with shift off
  (Instagram DM evidently sets no auto-capitalization). KeyboardKit is not honoring the field's
  `autocapitalizationType`, or caps at sentence start regardless.
- Active shift key: KeyboardKit draws a black glyph on a gray key; Apple draws a white key with a black glyph.
- Bottom row: Apple has `123 | emoji | space | return`; KeyboardKit has no emoji key (free 9.9.1 emoji keyboard is a
  placeholder). Space: Apple shows no label (small language mark), KeyboardKit shows "space".
- Glass container, corner radius, key color, globe and dictation glyphs: match by eye.
- Haptics: KeyboardKit vibrates on key press although the user has keyboard haptics off. A keyboard extension
  cannot read that system setting, so default haptics OFF and offer a toggle in the container app.

Consequences for the re-plan (Sprint 3):
- Height: shrink the toolbar to Apple's 51 pt band and keys to 43 pt at 54 pt pitch; target container height
  equal to Apple's within 2 pt on the 390 pt screen. Re-measure on screenshots as the success check.
- Replace space drag with continuous cursor movement (accumulate fractional offset, move per ~8 pt with no step
  threshold delay), or tune KeyboardKit's space-drag sensitivity, and compare by feel.
- Auto-capitalization must follow `textDocumentProxy.autocapitalizationType`; shift-active key colors fixed in KKColor.
- Emoji key in the bottom row that calls `advanceToNextInputMode` toward Emoji (Sprint 2 Next-key finding).

## Task 2.5 gate: PASS (2026-10-28)

Task 2.3 checklist items 1-3 passed (334ce92) and KeyboardKit loads and types (2.4 Step 7.1). Free Apple ID +
xtool + vendored KeyboardKit 9.9.1 is the toolchain for Sprints 3-6. Next: re-run plan-flow for Sprints 3-6.

## Sprint 3: detector after the shorthand rules

Measured 2026-10-29 with the same command as Sprint 1 (priorBonus 2.0):

```
chat.txt korean: 67 words, accuracy 98.51%, words that flip while typing 20.9% | top errors: 걔x1
chat.txt english: 14 words, accuracy 100.00%, words that flip while typing 35.7% | top errors: 
tatoeba-eng.txt english: 16544 words, accuracy 99.55%, words that flip while typing 0.8% | top errors: Zirix44 Rimax16 clarifiesx1 Ddax1 Tizix1 glaivex1 SAFx1 Tatarx1
tatoeba-kor.txt korean: 8626 words, accuracy 99.83%, words that flip while typing 0.5% | top errors: 꽤x6 걔x4 새x4 뜰x1
tatoeba-kor.txt english: 5 words, accuracy 100.00%, words that flip while typing 40.0% | top errors: 
```

The six gap words from the Sprint 1 review are fixed except 걔 (keys `rO` = "ro", a short-syllable clash
that the prior cannot beat). 아+ㅋㅋ typed in one go composes as 앜ㅋ, like Apple's keyboard.
Mixed tokens (nice하더라) stay a known loss: a word is one language; the bar flip fixes a wrong word.

Quality review fixes (2026-10-29), eval unchanged on every line:
- 그래ㅋㅋ좋아 typed in one go composes as 그랰ㅋ좋아. The lone ㅋ before 좋 used to make the word invalid
  Hangul, so it committed as English. A glue run now counts the preceding syllable's matching final (ㅋ/ㅎ).
- Without word lists (load failure or the first 136 ms), valid Hangul commits as Korean even after an
  English word; while typing it still keeps the previous language.
- An abandoned word (keyboard hidden, message sent, cursor moved) sets the previous language, so the next
  message starts in the language just used.
- 40 tests (3 added: glue after a final, abandon after a flip, typing after a commit ends the flip).

## Sprint 4: keyboard on the phone

Checked 2026-10-29 on the iPhone 13 Pro (iOS 26, dark mode), Instagram DM unless noted. Builds 628e865,
dd4b394, 5b9aa7c and the input-callout patch.

| # | Item | Result |
|---|------|--------|
| 1 | `안녕 내일 봐` from an empty field | PASS (so `!p.hasText` in `noticeFieldMoved` stays) |
| 2 | ` see you tomorrow` | PASS by replay: the field showed `ㄴㄴㄷ`, which is `sse` typed as Korean; TypingSession turns `see` into ㄴ -> se -> see |
| 3 | `오늘 meeting 몇시야 ㅋㅋ진짜` | PASS |
| 4 | `각` + backspaces | PASS: 가, then normal per-character deletes after the space |
| 5 | Bar flip while typing and after the space | PASS (Ekdhavyfh -> 단어가, Tmvpdltm flips after the space) |
| 6 | Shift, caps lock, ㅃㅉㄸㄲㅆ | PASS |
| 7 | Empty-field case | Capital at a start, like Apple. The user keeps autocap off: protly now disables it |
| 8 | Emoji key | FAIL as designed: `advanceToNextInputMode` goes to whatever iOS puts next (English (Canada)), and reordering in Settings does not change it. With Protly + Emoji only, iOS puts its own emoji key bottom left. The user's call: the in-row key becomes the protly key in Sprint 5 |
| 9 | Space label, haptics, shift look | PASS after fix: Apple iOS 26 shift is the same gray key with a white filled arrow (protly had a white key, then a black arrow) |
| 10 | Space drag | Worse than Apple: steps stall between characters, no vertical movement. A keyboard can only move the cursor by character offsets; Sprint 6 |
| 11 | Double space period | PASS |
| 12 | Half word survives hide/reopen | PASS |
| 13 | KakaoTalk and Messages | PASS |
| 14 | Crash / fallback | none |
| 15 | Screenshots | measured below |
| 16-19 | Send with no space, cursor tap, `안녕 ` backspace, apostrophes | PASS |
| 20 | English underline | acceptable |

Also seen: `걍` (keys `rid`) commits as English "rid": 걍 is rare in the word lists. Carry into the Sprint 6
detector work with 걔. Key pop-ups (input callouts) on row 1 were cut off at the keyboard's top edge; the user asked
to remove them, done as a KeyboardKit patch (VENDORED.md).

Geometry (pt, from 1170x2532 screenshots, Apple's English (Canada) keyboard vs protly):

| | Apple | protly round 1 | protly final |
|---|---|---|---|
| Band above row 1 | 52.0 | 51.67 | 51.67 |
| Row pitch / key height | 54 / 43 | 54 / 43 | 54 / 43 |
| Band below the last row | 71.0 | 80.33 | 74.83 |
| Key pitch across / edge margin | 38.3 / 7.33 | 39 / 4 | 38.26 / 7.33 |

- `bottomInset` never moved anything: KeyboardKit applies `keyboardViewStyle.edgeInsets` as padding inside a
  fixed-height frame, and sizes keys from the full width. Side margins are now padding outside `KeyboardView`;
  the last row's frame is trimmed so its key rests on the view's bottom edge.
- 74.83 is the floor: iOS clips a third-party keyboard to its view and draws the globe/mic band (taller than
  Apple's own) under it. Trimming the full 9.33 pt clipped the bottom row. So all rows sit 3.8 pt higher than
  Apple's; the alternative is a 3.8 pt shorter bottom row. The user accepted the current look.

Sprint 4 gate: items 1, 2, 4, 5, 9, 12, 13, 14, 16, 17, 18 pass; item 8 is replaced by the protly key in Sprint 5
(the system key opens Emoji); band below is 3.8 pt off for the platform reason above, accepted by the user.

## Sprint 5: actions

Checked 2026-10-29 on the iPhone 13 Pro (iOS 26, dark mode), builds 1a53c7f to 62a4d02. The user reported "mostly
works" for the Task 5.4 checklist; item 7 (latency) "not slow", no seconds measured. Found on the phone and fixed:

- Row 1 long-press bubbles (action callouts) were cut at the keyboard's top edge: the bubble (55 pt) was taller
  than the room above the key (34.5 pt). The vendored `Callouts+ActionCallout.swift` now shrinks such a bubble to
  fit (1a53c7f).
- An empty left bar slot collapsed (an `if` with no else draws nothing), so Translate slid to the left quarter
  (90e19b2).
- The band above row 1 was 52 pt on first open and 35 pt after an Emoji round-trip: the view's content was
  239.5 pt and iOS only sometimes added 17.5 pt above it. 62a4d02 made the content 257 pt (`topBand`), but the
  user still sees the height change ("sometimes taller, sometimes shorter").
- Quality review fixes (e420200): a cancelled field read stops at once; a partial read is refused with "Select
  all, then tap again"; a selection gets its own mode; Read clipboard only on an empty field.

The height instability moves to the cloud campaign 2026-10-29-keyboard-visual
(`docs/plans/2026-10-29-keyboard-visual.md`): simulator screenshots measured against Apple's keyboard, so the
fix is verified by Claude rather than by the user's eye. Sprint 5's features pass; Sprint 6 is planned meanwhile.

## Simulator verification

Campaign 2026-10-29-keyboard-visual, sprint 001 (`docs/plans/2026-10-29-keyboard-visual.md`). The workflow
`.github/workflows/keyboard-shots.yml` (`ios-app/CI/README.md`) builds a CI host app with the ProtlyKeyboard
sources, screenshots 7 scenarios and measures them with `ios-app/CI/measure.py`; every run is on the branch
`ci-shots` under `runs/<sha7>-<run>/` with `report.txt`, the PNGs, `ui-log.txt`, accessibility trees and, from
run 4, `keyboard-log.txt` (ProtlyHeight's debug log).

Setup: GitHub `macos-26` runner, Xcode 26.6 (17F113), iOS 26.5 simulator runtime, iPhone 13 Pro (390 x 844 pt,
3x), dark mode, English (US). Protly was enabled by writing `AppleKeyboards` (Protly, Emoji, English (US)) into the
shut-down simulator's global preferences: the Settings fallback was never needed. Switching keyboards uses the
globe's long-press list ("Protly, Korean", "Emoji", "English (US)"): a plain globe tap's order changes after an
app switch, and iOS 26's Emoji keyboard has no ABC key.

### Final measurements (run 7, `runs/18a85b4-7`, RESULT PASS; run 5 measured the same)

Points; top = keyboard glass top edge from the screen top; band = top edge to the top of row 1's keys.

| Scenario | Keyboard | Top | Band | Row pitch | Key height | Bar text centers |
|---|---|---|---|---|---|---|
| 01-apple | Apple English (US) | 509.00 | 52.00 | 54.00 | 43.00 | 65.0, 194.8, 325.0 (predictions) |
| 02-first-open | Protly | 512.00 | 52.00 | 54.00 | 43.00 | none |
| 03-after-emoji | Protly | 512.00 | 52.00 | 54.00 | 43.00 | none |
| 04-after-background | Protly | 512.00 | 52.00 | 54.00 | 43.00 | none |
| 05-after-second-emoji | Protly | 512.00 | 52.00 | 54.00 | 43.00 | none |
| 06-word-typed | Protly | 512.00 | 52.00 | 54.00 | 43.00 | 67.5 (flip), 195.3 (Polish) |
| 07-empty-left-slot | Protly | 512.00 | 52.00 | 54.00 | 43.00 | 195.3 (Polish) |

The 3 pt between Apple's top (509) and Protly's (512) is the band under the last row (Apple 71, Protly 74.83,
Sprint 4): accepted by the user. The empty left slot keeps its third: Polish is 0.33 pt from the screen center.

### Rounds

| Run | Commit | Keyboard change | Result |
|---|---|---|---|
| 1 | ec71172 | none (baseline) | Reproduced the phone: top 512 on first open, 495 (band 69) after the Emoji round-trip and after the app switch. 05-07 caught Apple's keyboard (test flow, fixed in run 2) |
| 2 | 0db92c8 | Round 1: `ProtlyHeight` pins the view to 257 pt in portrait (priority 999) | Emoji round-trips fixed (512). After the app switch still 495 |
| 3 | 06c3c10 | Round 2: vendored hosting controller ignores safe areas | No change: not a safe-area inset. Reverted in round 3 |
| 4 | 4d93222 | Round 3: `allowsSelfSizing`, pin re-asserted when the host returns, debug log | No change. The log shows the view at 257 pt in every presentation with no system constraint against the pin |
| 5 | 7a84a02 | Round 4: after `NSExtensionHostDidBecomeActive` the pin drops by 17 pt; `ProtlyRoot` keeps the content at the bottom | PASS |
| 6 | cf3e979 | Review fix: drop only before the view's first layout at the pinned height (the notification also arrives over a live keyboard). Workflow: requires `STATUS measured`, checkout keeps no token | FAIL: the app-switch controller was laid out at 257 pt 27 ms before the notification, so 04 kept the 17 pt band |
| 7 | 18a85b4 | Review fix: drop only within 2 s of the controller loading (the notification came 0.22-0.28 s after loading in runs 5-7) and while the portrait pin is active | PASS |

What the trees and the log showed: iOS draws its glass 17 pt above the height of its own `inputView` placeholder
for a third-party keyboard. On a fresh presentation (first open, Emoji round-trip, relaunch) the placeholder is the
keyboard's height minus those 17 pt, so the glass starts at the view's top. When the host app returns from the
background with the keyboard up, iOS attaches a new keyboard controller to the kept presentation, the placeholder is
the full 257 pt, and the 17 pt margin becomes empty band above the view. In the scenarios
`NSExtensionHostDidBecomeActive` arrives only on that path, 0.22-0.28 s after the new controller loads; there the
pin is 240 pt and the bar band's empty top 17 pt sits under iOS's margin. On the phone the notification also comes
over a live keyboard (Control Center, alerts, Face ID), so a controller older than 2 s ignores it. Before
62a4d02 the view was 239.5 pt with no pin, which is why the phone showed 52 or 35 pt depending on the path.

### What the simulator cannot show

- The phone: other hosts (Instagram, KakaoTalk, Messages), iOS 26 builds other than 26.5, and the 17 pt margin
  itself (the phone links the iOS 27.1 SDK; Sprint 5 saw 17.5 pt). ProtlyHeight's log (Console, subsystem
  `com.northprot.protly`, category `height`) shows each presentation: after an app switch it must read
  `host became active` and then `bounds: height 240`; over Control Center or an alert, `host became active after
  N s, kept`. If a fresh presentation (a cold launch that opens the keyboard at once) gets the notification within
  2 s, the band would be 35 pt (240 - 17); the relaunch scenario (07) did not receive it. The same holds for a
  notification reply or Control Center closed within 2 s of the keyboard appearing.
- After an app switch that controller keeps the 240 pt pin. Every simulator presentation made a new controller,
  but none hid and re-showed the keyboard in the same host. On the phone: after an app switch, send (hide) and tap
  the field again; if the log shows no new `pinned` line and the height stays 240, reset the pin to 257 in
  `viewWillDisappear`.
- Run 6's order (first layout at 257 pt before the notification) has not run with the age guard: in run 7 the
  notification came first. Runs 5 and 7 are partial evidence that a late drop works: after the drop iOS laid the
  view out at 257 pt once more, then settled at 240.
- After an app switch the view's top 17 pt (the empty top of the bar's band) are under iOS's margin. The vendored
  long-press bubble counts 34.5 pt of room above row 1 (bar and inset, not the band), which stays visible; check a
  row 1 bubble after an app switch on the phone.
- Landscape (the pin is portrait only), the row 1 long-press bubble in general and Hangul keycap rendering on the
  device are checked by the tower on the phone.

## Sprint 6: detector carry-overs

Measured 2026-10-29 with the same command (priorBonus 2.0):

```
chat.txt korean: 67 words, accuracy 100.00%, words that flip while typing 17.9% | top errors: 
chat.txt english: 14 words, accuracy 100.00%, words that flip while typing 35.7% | top errors: 
tatoeba-eng.txt english: 16544 words, accuracy 99.55%, words that flip while typing 0.8% | top errors: Zirix44 Rimax16 Aksaix1 glaivex1 garagedx1 Sorosx1 Ddax1 RSFx1
tatoeba-kor.txt korean: 8626 words, accuracy 99.95%, words that flip while typing 0.3% | top errors: 새x4
tatoeba-kor.txt english: 5 words, accuracy 100.00%, words that flip while typing 40.0% | top errors: 
```

Before this sprint (same command on main plus security 002): chat korean 98.51% (걔x1), tatoeba-kor 99.83%
(꽤x6 걔x4 새x4 뜰x1), tatoeba-eng 99.55%. 걍 걔 꽤 얘 쟤 뜰 joined the Korean list at count 400 (missing from
ko_50k), and a manual shift on a doubled-jamo key inside a word is Korean unless every key is shifted. 새 (keys
`to`) stays a known loss; the flip fixes it.

## Sprint 7: style eval

Live run of `scripts/eval-polish.mjs` on 2026-10-29 at c65af65 (7a, its review follow-up and the merge of main):
`0 failure(s) of 16`. The extension cases use `claude-sonnet-5-5`, the keyboard cases `claude-opus-5-5` at low
effort. `in` and `out` are the API's own `input_tokens` and `output_tokens`, which replace the character estimates
of the Sprint 7 size table.

| Case | Result | in | out |
|---|---|---|---|
| polish chat, typos | PASS | 1,132 | 140 |
| polish chat, CyanStyle rules | PASS | 1,138 | 147 |
| polish email, greeting and paragraphs kept | PASS | 1,217 | 285 |
| out, female friend in Russian (runs 1-3) | PASS x3 | 751 each | 59, 60, 60 |
| out, English style: Canadian spelling, no dash or semicolon | PASS | 1,240 | 69 |
| out, English style: adds no exclamation mark or emoji | PASS | 1,235 | 68 |
| email, English style: no banned service phrases | PASS | 1,241 | 79 |
| keyboard out, the style keeps a warm draft warm | PASS | 1,618 | 31 |
| keyboard out, ㅋㅋ becomes English laughter | PASS | 1,627 | 47 |
| keyboard out, style without a note | PASS | 1,625 | 49 |
| keyboard fix, CyanStyle rules | PASS | 1,629 | 126 |
| keyboard out, about-me note spells the school, adds nothing | PASS | 1,697 | 51 |
| keyboard fix, about-me note never leaks into the polish | PASS | 1,688 | 84 |
| out, never Korean | PASS | 1,224 | 34 |

- Real input sizes: the keyboard prompt is about 1,620 tokens per call without a note and about 1,690 with the
  eval's 101-character note (the user message is a few tokens of that). Extension English outgoing is about 1,240,
  the Russian outgoing prompt 751 (it gained the Korean chat marks line), Polish about 1,140.
- Totals: 20,564 input and 1,389 output tokens. Cost about $0.11 [estimate from list prices, not billed figures].
  The first run, before the review follow-up (15 cases at 64b10f7), cost about $0.10.
- Korean chat marks: the warm draft now reads "I miss you :(", `ㅋㅋㅋ` became "lol", and `ㅋㅋ 진짜?` became
  "haha really?". In the first run the keyboard had kept `ㅠㅠ` as is ("I miss you ㅠㅠ").

## Sprint 7: style eval with the user's own style (2026-10-29)

Live run of `scripts/eval-polish.mjs` on 2026-10-29 at 18fbbee (rebased on main 9443d17, so with the 7b about_writer tags), after Cyan's own four style blocks (ENGLISH_STYLE,
POLISH_VOICE, TRANSLATE_TONE, EMAIL_SHAPE) replaced the 7a blocks: `0 failure(s) of 16`. Same models and effort as
above. Two checks are stricter than in the first table: `ㅋㅋ` must not become "haha" (the user's tone line says
"lol" or dropped), in the keyboard case and in the extension's `out, never Korean` case.

| Case | Result | in | out |
|---|---|---|---|
| polish chat, typos | PASS | 1,211 | 118 |
| polish chat, CyanStyle rules | PASS | 1,217 | 157 |
| polish email, greeting and paragraphs kept | PASS | 1,296 | 252 |
| out, female friend in Russian (runs 1-3) | PASS x3 | 776 each | 64, 58, 58 |
| out, English style: Canadian spelling, no dash or semicolon | PASS | 1,299 | 73 |
| out, English style: adds no exclamation mark or emoji | PASS | 1,294 | 70 |
| email, English style: no banned service phrases | PASS | 1,285 | 79 |
| keyboard out, the style keeps a warm draft warm | PASS | 1,646 | 31 |
| keyboard out, ㅋㅋ becomes lol or is dropped | PASS | 1,655 | 47 |
| keyboard out, style without a note | PASS | 1,653 | 49 |
| keyboard fix, CyanStyle rules | PASS | 1,657 | 126 |
| keyboard out, about-me note spells the school, adds nothing | PASS | 1,749 | 51 |
| keyboard fix, about-me note never leaks into the polish | PASS | 1,740 | 76 |
| out, never Korean, ㅋㅋ never haha | PASS | 1,283 | 34 |

- Prompt sizes (system text, characters): keyboard 3,871 with the final newline (was 3,822, budget 3,900),
  extension Polish 2,682, outgoing and box with `lang` en 2,773, Russian outgoing 1,336, email 2,691. The keyboard
  costs about 30 more input tokens per call than before, the extension Polish and English outgoing about 60-80.
- Totals: 21,313 input and 1,343 output tokens. Cost about $0.11 [estimate from list prices, not billed figures].
- Korean chat marks: `ㅋㅋㅋ` became "lol", `ㅋㅋ 진짜?` became "lol really?" (it was "haha really?" before), and
  the warm draft reads "I miss you :(".
- The new POLISH_VOICE "ask goes first" shows in the email case: "i wanted to ask if its possible to submit ... on
  monday" became "Could I submit the lab report on Monday instead of Friday?", with the paragraphs, greeting and
  sign-off kept.
- Watch, not failed by any check: the note-free fix of "im running late, see you at 3" came back as two sentences
  ("I'm running late. See you at 3."), although ENGLISH_STYLE says "clauses the draft joins stay joined". A run
  before the rebase kept the comma. The Russian runs added an emoji the draft lacks (that prompt has no
  ENGLISH_STYLE, as before).

## Sprint 8: target eval (2026-10-29)

Live run of `scripts/eval-polish.mjs` on 2026-10-29 on branch `sprint8` at 4738f83 (Tasks 8.1-8.4 on main
12e27d1): `0 failure(s) of 24`. Same models and effort as above. The eight new cases are all keyboard cases; the
four older keyboard MODE out cases now send `TARGET: English` and are the English-target style check.

| Case | Result | in | out |
|---|---|---|---|
| polish chat, typos | PASS | 1,211 | 137 |
| polish chat, CyanStyle rules | PASS | 1,217 | 158 |
| polish email, greeting and paragraphs kept | PASS | 1,296 | 276 |
| out, female friend in Russian (runs 1-3) | PASS x3 | 776 each | 51, 60, 59 |
| out, English style: Canadian spelling, no dash or semicolon | PASS | 1,299 | 69 |
| out, English style: adds no exclamation mark or emoji | PASS | 1,294 | 70 |
| email, English style: no banned service phrases | PASS | 1,285 | 79 |
| keyboard out, the style keeps a warm draft warm | PASS | 1,825 | 38 |
| keyboard out, ㅋㅋ becomes lol or is dropped | PASS | 1,834 | 45 |
| keyboard out, style without a note | PASS | 1,832 | 49 |
| keyboard fix, CyanStyle rules | PASS | 1,829 | 142 |
| keyboard out, about-me note spells the school, adds nothing | PASS | 1,928 | 51 |
| keyboard fix, about-me note never leaks into the polish | PASS | 1,912 | 66 |
| keyboard out, ru: prefix, the male writer in Russian past tense | PASS | 1,832 | 52 |
| keyboard out, ru: prefix, a female friend (누나) saved the writer (runs 1-3) | PASS x3 | 1,834 each | 54, 60, 58 |
| keyboard out, ja: prefix, ㅋㅋ rendered in Japanese | PASS | 1,842 | 64 |
| keyboard out, es: prefix, masculine adjectives for the writer | PASS | 1,840 | 68 |
| keyboard fix, ko: polishes a Korean draft in Korean | PASS | 1,839 | 144 |
| keyboard fix, a Spanish draft stays Spanish, without the English style | PASS | 1,831 | 116 |
| out, never Korean, ㅋㅋ never haha | PASS | 1,283 | 34 |

- Prompt size: the bundled keyboard prompt is 4,280 characters with the final newline (was 3,871, budget now
  4,300). Measured cost of that: the keyboard cases read 1,825-1,842 input tokens without the note and 1,912-1,928
  with it, against 1,646-1,657 and 1,740-1,749 in the Sprint 7 run, so about 180 more input tokens per call. The
  plan estimated about 100 (characters / 4); the Hangul and Cyrillic in the new lines cost more per character.
  The extension cases are unchanged to the token.
- Totals: 37,059 input and 2,000 output tokens. Cost about $0.20 [estimate from list prices, not billed figures].
- Targets: Russian past tense is masculine for the writer ("устал ... лёг") and feminine for 누나 ("ты меня
  спасла", three of three); Japanese renders ㅋㅋ as "w"; Spanish uses "cansado".
- Polish: the `ko:` draft came back Korean, in banmal, with ㅋㅋ kept and 돼, 안 되면, 말해 줘 fixed; the Korean
  change list names each fix. The Spanish draft stayed Spanish ("color", "¿dónde la compraste? jaja"), with no
  English style applied.
- Watch, not failed by any check: the `ko:` polish also turned the chat form 낼 into 내일, which is more formal
  than the draft (spelling is right, register drifts a little). The Russian female-friend runs added "!" and
  "просто", which the draft does not have; the non-English MODE out has no emoji and exclamation rule, as in the
  extension.

## Simulator phone checks

Campaign 2026-10-30-sim-phone-checks, sprint 001 (`docs/plans/2026-10-30-sim-phone-checks.md`). The phone checks
of Tasks 6.8 and 8.5 (feature plan) that need no network, the flip-over-whitespace rule (997f108), memory and the
app icon run in the simulator job after the layout scenarios (`ios-app/CI/README.md`, "Phone checks"). Each item
is one `CHECK <id> PASS|FAIL|RECORD|SKIP <evidence>` line in `checks.txt` and in the report's `CHECKS` section,
with `c-<id>.png` (and `c-<id>-<n>-<slot>.png` per bar reading) in the run folder.

Setup: GitHub `macos-26` runner, Xcode 26.6 (17F113), iOS 26.5 simulator runtime, iPhone 13 Pro (390 x 844 pt,
3x), dark mode, English (US). Runs: `runs/b390712-8` (probe), `runs/f0d0943-9`, `runs/307483a-12`,
`runs/083f4c9-14` and the final `runs/e301e04-15` (`STATUS measured`, layout `RESULT PASS`,
`CHECKS pass 13 fail 1 record 6 skip 1`). The table is from the final run; runs 9 to 15 gave the same result per
ID (6.8-7 and 8.5-9o run with their language context from run 9 on).

### Results

Field text is read through XCUITest (exact); bar labels with Vision OCR in the UI test (quoted as OCR).

| ID | Result | Evidence |
|---|---|---|
| 6.8-1 | PASS | field `i dont think its ok teh.` exactly; `teh`: right slot OCR `the`, tap: field `the ` |
| 6.8-2 | PASS | `recieve`: right slot OCR `receive`; `.`: field `recieve.` |
| 6.8-3 | PASS | `tomo`: right slot OCR `tomorrow`, tap: field `tomorrow ` |
| 6.8-4 | PASS | `안녀`: right slot OCR `안녕`; `안녕ㅎ` + right slot: field `안녕하세요 ` |
| 6.8-5 | RECORD | `omw`: right slot empty (the simulator has no `omw` text replacement), space: field `omw ` |
| 6.8-6 | SKIP | no contacts in the simulator |
| 6.8-7 | PASS | after a Korean word: `걍 가자`, `걔 진짜 웃겨`, `얘 뭐야`, `꽤 좋다` all Korean; `I need to get rid of it` all English |
| 6.8-8 | PASS | `wyd`: field `죵`; left slot: `wyd`; space, clear, `wyd `: field `wyd ` |
| 6.8-9 | RECORD | host terminated and relaunched: `wyd ` English; same keyboard process (pid unchanged), so this shows the learned word survives a new host, not a new keyboard process |
| 6.8-10 | RECORD | 30 rounds, each hiding the keyboard and bringing Protly back: footprint 60 -> 63 MB (+3 MB; runs 9 to 14: +0, -1, -2), same pid; macOS-side `footprint`, whole MB |
| 6.8-11 | PASS | flip part: `내일 봐`, left slot: field `내일 qhk` (Translate is sprint 002's) |
| ws-1 | PASS | `hello `: left slot OCR `ㅗ디 \|ㅐ` (Hangul); tap: field `ㅗ디ㅣㅐ ` |
| ws-2 | PASS | field `hello. `: left slot empty (no OCR text, ink 0) |
| ws-3 | PASS | field `hello` + newline: left slot empty (no OCR text, ink 0) |
| 8.5-1o | PASS | `ru` came out Latin (no flip); field `ru: 누나 노트 고마워 누나 덕분에 살았다 `: center OCR `Translate` |
| 8.5-2o | RECORD | `ru` again at the start: `겨`; `zh` came out `코`, flipped to `zh`, `zh: 안녕 `; then `zh ` alone: `zh ` (Latin: the flip taught it) |
| 8.5-6o | PASS | `ok` Latin; field `ok: 내일 봐 `: center OCR `Translate` |
| 8.5-7o | PASS | `ko` Latin; field `ko: 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠 `: center OCR `Polish` |
| 8.5-8o | RECORD | three-paragraph `ko:` draft, cursor after `ㅠㅠ`: center empty (the last word is still being typed) |
| 8.5-9o | FAIL | keyboard: after an English word, the draft came out `me 둧뭇ㅁ 디 color de tu 촘볃ㅅㅁ, donde la conprastes? jaja `, so the center offers `Translate`, not `Polish` |
| icon | RECORD | `Protly` on home page 1 at {296, 163, 68, 90.7}; `c-icon.png` for the tower |

### Findings for the tower (keyboard behaviour, not fixed here)

- 8.5-9o: Spanish words that are not English words (`encanta`, `el`, `chaqueta`) are read as Korean even after an
  English word, and `the` at a message start after Korean text came out `솓` (flipped for the context). On the
  phone the user would flip each of them before Polish appears.
- A draft offers Translate or Polish only once its last word is ended: while a word is being typed the bar offers
  no action (`refreshField`). The checklist's "type `ru: ...`: the center shows Translate" holds after a space (the
  tests add one); with the cursor right after the last letter (8.5-8o) the center is empty.
- Layout scenario 04 (after an app switch) is intermittent: `runs/b390712-8` and `runs/307483a-12` measured a 69 pt
  band, `runs/f0d0943-9`, `runs/083f4c9-14` and `runs/e301e04-15` 52 pt. In the failing runs the controller the host attaches after the switch never logged
  `host became active` (ProtlyHeight's drop needs `NSExtensionHostDidBecomeActive` within 2 s of loading). Run 8
  had the memory sampler attached; run 12 did not (it starts with the phone checks), so the sampler is not the
  cause. When the notification does not come, the keyboard keeps the 17 pt band; on a slow phone the same can
  happen.
- A slow extension start shows Apple's Korean keyboard instead: in runs 12 and 14 (layout scenarios 197 s and
  247 s against 81-98 s) the first presentation was Apple's Korean keyboard (`한` on the space bar), iOS's stand-in
  for Protly's primary language, and run 14 then lost the keyboard after Emoji (03 found none). The driver had
  measured that stand-in as Protly (02 at 509 pt); since `e301e04` a keyboard whose keys XCUITest can see, other
  than English and Emoji, is `system-keyboard`; at the first open (02) and at the start of each phone-check group the
  tests wait up to 20 s for Protly to take over (if it does not, 02 comes from a pick in the globe list, logged in
  `ui-log.txt`), and a stand-in anywhere else fails its scenario or check. The final run had no stand-in. On the phone this would be a first open right after install or a memory kill.
- 8.5-2o: `ru` at the start came out Latin in 8.5-1o and as `겨` in 8.5-2o: the previous message's language decides
  (8.5-1o followed English text, 8.5-2o followed `ru: ` + Korean). `zh` needed the flip once and then stayed Latin.
- 6.8-7 depends on context: in `runs/b390712-8`, right after `omw ` (English), `걍` came out `rid`. After a Korean
  word all four phrases are Korean, as the checklist ("in a Korean conversation") expects.

### Probe (`runs/b390712-8`)

- Vision works inside the UI test on the iOS 26.5 simulator: `.accurate` offers ko-KR and en-US among 30
  languages; a self-test on drawn text reads `Polish 안녕하세요`; the bar after `hello ` read `"ㅗ디 |ㅐ"` (left)
  and `Polish` (center), the field `안녕`. No pixel-signature fallback was needed (`OCR_FALLBACK=1` keeps it).
- `123` layer (`probe-123.png`): KeyboardKit's iPhone numeric layout; rows 1-2 have 10 keys on the letter pitch
  (colon at x 99.3 pt), row 3 has `. , ? ! ’` at 14% of the width each (x 87.9, 141.4, 195.0, 248.6, 302.2 pt).
  `:`, `?`, `,`, `.`, `!` each typed at its computed position. Space goes back to the letters; otherwise the test
  taps `ABC` (same place as `123`).
- Memory from the macOS side: `pgrep -x ProtlyCIKeyboard` finds one process; `footprint -p` and `sudo footprint -p`
  both print it (54 MB at first), `ps -o rss=` prints 295600 KB (shared pages counted), and `vmmap --summary` hung
  for 20 s (it suspends its target). The sampler uses `footprint` every 2 s, during the phone checks only.

### What the simulator cannot show

- Memory: the numbers are the simulator process's footprint on macOS in whole MB, not the phone's jetsam ledger;
  the 40 MB limit and the 10 MB growth line are judged on the device. The pid did not change over 30
  presentations, and the keyboard process survived the host's relaunch (6.8-9 RECORD), so a cold keyboard start is
  not covered.
- 6.8-5 text replacements and 6.8-6 contact names: the simulator has none; the phone's own (`omw`, `ㄱㅅㄱㅅ`,
  names) are the tower's.
- The icon on the real home screen (the crop is the simulator's rendering of the same `AppIcon.png`).
- Other host apps (Messages, KakaoTalk, Instagram), typing feel and haptics.

### Sprint 002: network checks (Full Access, CI key, container app)

Campaign 2026-10-30-sim-phone-checks, sprint 002. Same runner, Xcode, runtime and device as sprint 001. The
workflow writes `Secrets.swift` from the Actions secret `PROTLY_API_KEY` (a CI-only key) through
`make-secrets.sh`; a run with the key only restores the DerivedData cache, never saves it (`network key: present
(CI key); DerivedData cache: restore only, not saved in this run` in each report), and the leak guard writes
`LEAK-GUARD pass: no key prefix in N files` before publishing. Runs: `runs/8a801d5-30` (probe 1),
`runs/79473e5-34`, run 35 (cancelled by a push), run 36 (hung, hit the 80-minute job limit, nothing published),
`runs/c6d83a1-40` (probe 2), `runs/067c1cd-41`, `runs/30a1fbf-44` (the full run of record), run 48 (cancelled by
a push) and the closing run `runs/ec69307-50`. Under the tower's closing rule (TOWER-CLOSE-RULE-2), `runs/30a1fbf-44`
(`CHECKS pass 25 fail 1 record 8 skip 2`; its one FAIL is 8.5-7 under the rule before the tower's ruling, and its
layout test stopped at launch) is the record for every check it measured, and the filtered closing run
`runs/ec69307-50` (`[shots:KeyboardShotsUITests,PhoneChecksUITests/test6_85net]`, `STATUS measured`, layout
`RESULT PASS` with every band at +0, `CHECKS pass 8 fail 0 record 1 skip 0 not-run 27`, leak guard on 63 files)
proves the layout and the 8.5 network IDs. 8.5-3 to 8.5-9 passed in both runs with the same outputs or
near ones; the evidence quotes run 44 unless it names run 50.

| ID | Result | Evidence |
|---|---|---|
| 6.8-11 | PASS | `내일 봐` typed as `ghk` + flip, center Translate: `Translating`, Insert after 4.0 s: `Thanks so much for today` (Latin) |
| 8.5-1 | PASS | `ru: 누나 노트 고마워 누나 덕분에 살았다` (`ru` came out `겨`, flipped): `Translating`; run 50's first try inserted `Спасибо за конспект! Ты меня спасла.ㅋ` (a Hangul `ㅋ`: rule fail), the retry `Спасибо за конспект! Ты меня спасла` after 3.3 s with a Hangul back translation in the panel (RECORD); Undo: the field equals the draft again (run 44: first try, 4.5 s) |
| 8.5-3 | PASS | `ja:`: `明日ひま？一緒にご飯行こうよw` (kana and kanji, no `ㅋ`, no `lol`), 3.4 s |
| 8.5-4 | PASS | `es:`: `Hoy estoy muy cansado`, 4.6 s |
| 8.5-5 | PASS | `내일 3시에 봐`: `See you tomorrow at 3`, 3.0 s |
| 8.5-6 | PASS | `ok: 내일 봐`: `ok, see you tomorrow`, 3.0 s |
| 8.5-7 | PASS | run 50: `Polishing`, 3.4 s: `내일 시간 돼? 같이 밥 먹자 ㅋㅋ 안 되면 말해 줘`. The model always writes the spaced `말해 줘` (runs 41, 44, 50); the tower ruled both spellings correct (plan row updated), and run 44's FAIL was under the earlier rule. Change lines (RECORD): `되? -> 돼? (맞춤법)`, `말해죠 -> 말해 줘 (맞춤법)`, `낼 -> 내일, 밥먹자 -> 밥 먹자 (띄어쓰기)` |
| 8.5-8 | PASS | three-paragraph `ko:` draft: `Polishing`, 3.4 s, `오늘 진짜 길었어\n\n낼 아침에 전화할게\n\n늦으면 미안 ㅠㅠ` (paragraphs kept, no `ko:`); panel: `고칠 부분이 거의 없어서 그대로 뒀어요.` |
| 8.5-9 | PASS | Spanish polish: `Me encanta el color de tu chaqueta, ¿dónde la compraste? jaja` (no `colour`, no `conprastes`), 4.1 s |
| 8.5-10 | RECORD | 8.5-1 tap to `Insert`: 4.0 s and 3.3 s in run 50 (run 44: 4.5 s, 4.2 s; run 41: 3.6 s, 3.2 s) |
| 7.7-1 | PASS | `ProtlyCIApp`: in-app Paste of the test note, counter `58 / 1,000` = 58; `Copy for the keyboard`: `Copied`; Read clipboard in the app's Test field, Allow Paste: `Save as your About me note (58 characters)?`; Save: `About me saved: 58 characters.`; Done: keys back, no panel text |
| 7.7-2 | PASS | `우리 문빔 킬른 다음 주에 오픈해` -> `Moonbeam Kiln opens next week` (no `pottery`, no `Victoria`), 2.7 s |
| 7.7-3 | PASS | `Can you send me the photos from yesterday?`, Read clipboard: `어제 찍은 사진 나한테 보내줄 수 있어?`; `protly about me v1` + `test`: `Save as your About me note (4 characters)?`, Cancel; 7.7-2 again: `Moonbeam Kiln opens next week`, 3.2 s |
| 7.7-4 | RECORD | 7.7-2 tap to `Insert`: 2.7 s and 3.2 s (7.7-2 and 7.7-3's repeat) |
| 7.7-5 | PASS | Select All, Cut: counter 0; Copy: `Copied`; Read clipboard: `Clear your About me note?`; Save: `About me cleared.`; the 7.7-1 copy and save again: 58 characters |
| 7.7-6 | SKIP | needs a phone reinstall |

Each run sends at most 14 requests (cap 60). Sprint 001's rows did not change in these runs; 8.5-9o now PASSes
(the Spanish flip fix on main) and 6.8-5 reads `On my way!` in the right slot in run 40 but nothing in runs 41
and 44 (the simulator's text replacements are not stable; RECORD either way).

### Sprint 002 findings

- Full Access: the Settings UI path works on iOS 26.5 (General > Keyboard > Keyboards > Protly > Allow Full Access
  > Allow; the switch takes two taps). The root list's rows are unlabeled cells around labeled buttons with
  identifiers like `com.apple.settings.general`, and the list may open scrolled to the bottom, so the test scrolls
  both ways until the row is on screen. Probe 2 (`runs/c6d83a1-40`) diffed the device's data folder around the
  switch (1068 and 1088 plists, each snapshot after `simctl shutdown`): no plist key for Full Access changed. TCC.db
  could not be read there (its rows were still in the -wal file, now copied too); this was not probed again, so
  the Settings UI stays the way.
- Allow Paste: the prompt is a SpringBoard alert, not the host's. In probe 2 the interruption monitor answered it;
  the phone checks tap `Allow Paste` in SpringBoard directly. While the prompt is up the keyboard is blocked in its
  clipboard read and the host does not answer accessibility queries (run 41: three 60 s snapshot timeouts on one
  tap), so nothing touches the host until the prompt is gone.
- The panel's buttons are found by OCR word boxes in the bottom 45 pt of the panel each time (probe 2: Cancel at
  x 22, Insert at x 321, y 741 pt), and the label match ignores case (Vision reads `Insert` as `insert`).
- Model output: 8.5-1's wording changes from run to run (`ты меня спасла` / `Ты меня реально спасла`) and 8.5-7's
  polish sometimes keeps `낼` (run 44's retry); the rules check what the plan asks, not one wording.
- The layout test once stopped at launch: `runs/30a1fbf-44` stopped in `app.launch()` 17 s in, before any shot,
  and the 200-line log tail did not say why. The same code passed in runs 41 and 50 (run 50 with every band at
  +0), so it counts as a flake until shown otherwise (tower ruling); `test-failures.txt` now keeps xcodebuild's
  error lines for the next one. Runs 30, 34, 40 and 41 measured the +17 pt band flake on one shot or two adjacent shots with `top-edge`
  495..512 pt, which the tower counts as layout PASS.

## Plain-text composition (typing-fixes 001)

Campaign 2026-10-30-typing-fixes, sprint 001 (`docs/plans/2026-10-30-typing-fixes.md`). The word being typed is
plain text in the field, as with Apple's Korean keyboard: no `setMarkedText` or `unmarkText` is left in the
keyboard (a source rule in `KeyboardSourceRulesTests` keeps it so). This removes the shared root of the Return,
edit-menu and dark-screen reports (`docs/research/2026-10-30-*.md`).

- **Writing.** `PlainWord.step` (ProtlyCore) turns each `FieldEdit` into proxy calls: delete the Characters after
  the part that stays, insert the new tail. 안녕하세요 takes 21 proxy calls for 12 keys. A commit sends only the
  difference (usually nothing), so Return after a word sends only `"\n"`.
- **Watching the field.** `FieldWatch.decide` (ProtlyCore) runs at every key, host callback and before any write
  over the word. It keeps a model of the text before the cursor from Protly's own writes (every state, including
  the one between the deletes and the insert). A selection or a changed after-context abandons; a context that
  ends with the model keeps (contexts are compared by their tails, so a cut field keeps); a context showing an
  earlier state keeps only until 150 ms after Protly wrote past it (a lagging web view), older abandons (a field
  that dropped the insert, a host undo); a context that matches nothing keeps only within 300 ms of the last write.
  `hasText` is not used. U+00A0 compares as a space. With no word typed, a selection forgets the committed word so
  a flip cannot delete it.
- **Abandon at a key.** The word stays as typed; the key starts a new word (it is not lost), and a backspace falls
  to KeyboardKit's normal delete. Hide and reopen mid-word: the half word stays as text and the next key starts a
  new word.
- **Host callbacks never write** (`textDidChange`, `selectionDidChange` and what they call; source rule).
- **`textDidChangeAsync`.** Its composing guard is gone: with autocap off, `preferredKeyboardCase` keeps the case,
  KeyboardKit's autocomplete service is disabled, and the context now includes the word.

Simulator: `runs/d504f77-25` (`STATUS measured`, layout `RESULT PASS`), every phone check that passed in
`runs/e301e04-15` passes, and 8.5-9o passes too (with sprint 002 merged). In `c-6.8-4-1-right.png` the word
being typed (`안녀`) has no underline; the same shot in `runs/e301e04-15` shows the blue marked-text underline.
`runs/28108ea-24` (same code) had every phone check pass but measured scenario 07 at a 69 pt band (top 495): the
same +17 pt as the scenario 04 flake above, with the keyboard's height log identical to `runs/e301e04-15`; the
re-run measured 52 pt. Scenario 07 can therefore show that flake too.

Phone checks the tower still owes: type in Instagram DM (dark), Messages, KakaoTalk, Safari and Chrome: no
underline, the word always visible, no split syllables while typing fast or slowly; Return after a word with no
space keeps the message in Safari and Chrome; double-tap or long-press on the last word shows Copy; a flip from
the bar after a word still works (also in a Safari contenteditable field); hide and reopen the keyboard mid-word,
then keep typing; a field with a length limit at its limit loses no character while typing.

## Space trackpad (typing-fixes 003)

Campaign 2026-10-30-typing-fixes, sprint 003 (`docs/plans/2026-10-30-typing-fixes.md`, research
`docs/research/2026-10-30-space-trackpad.md`). Protly's own drag math replaces KeyboardKit's (a fixed 5 pt per
character, no acceleration, every step dropped 50 pt above or below the start).

- **Math (R4).** `SpaceTrackpad` (ProtlyCore). Cost per grapheme by width: 6 pt narrow, 12 pt for Hangul (syllables
  and jamo), CJK, kana, fullwidth forms and emoji. The remainder carries between events. Speed gain: 1x up to
  100 pt/s, linear to 3x at 600 pt/s, capped there; the speed uses at least 1/120 s between events, so bunched
  callbacks do not read as a flick, and the gain never scales the carried remainder. Offsets are UTF-16
  units of whole graphemes (❤️ 2, 👨‍👩‍👧 8, 🇰🇷 4, 가 1), so the caret never lands inside an emoji. The caret stops at the
  ends of the snapshot and a push past an end is dropped, so the way back starts at once. A slow 60 pt drag moves 10
  Latin letters or 5 syllables; a 60 pt flick in 0.1 s moves 30 or 15.
- **Wiring.** `ProtlyActionHandler.handleDrag` takes `.space` while `isSpaceDragGestureActive`; other drags keep
  KeyboardKit's. The first drag event after the long press calls `beginSpaceDrag`: it reads the proxy, commits the
  word (the commit can change its reading), and builds the text before the cursor as that read with the written
  word swapped for the committed one (`SpaceTrackpad.textBefore`), because a read right after the commit may not
  show it yet. It also ends the bar's flip and Undo. That first event only sets the start, as in KeyboardKit. Every
  move goes through the controller's `adjustTextPosition` override, which forgets the `FieldWatch` model (source
  rule `testSpaceTrackpadWiring`). A hold with no drag event after it leaves the word as it was and types no space.
  The handler keeps the drag in `SpaceDrag` (ProtlyCore): a space press, release or end resets it, and so does a
  new touch start location, because a touch the system cancels mid-drag (a notification, Control Center) may send
  no release; without that the next drag would move from the old snapshot.
- **R1.** `SpaceTrackpad` ignores the finger's height, so a thumb drifting up or down keeps moving the cursor.
  KeyboardKit's handler is unused for space while the handler has its host; its `verticalThreshold` is set to
  `.greatestFiniteMagnitude` anyway, so the fallback never freezes either.
- **R3.** Space starts the trackpad after 0.4 s (`SpaceTrackpad.longPressDelay`, through
  `keyboardButtonGestureConfiguration` in `ProtlyRoot`'s `buttonView`); every other key keeps KeyboardKit's 0.5 s.
- **Not built.** R2 (haptic at trackpad start): haptics stay off in this campaign. R5 (skip refreshes during a
  drag): the simulator cannot show drag lag; build it only if phone check P6 finds a step costs more than ~4 ms.
  R6 (vertical movement): out of scope.
- **Limit.** The caret stops at the snapshot's ends (R4). A host whose after-context stops at a paragraph break
  (`FieldText.swift`) stops a rightward drag there; the before-context was whole in the hosts tested so far. If
  phone check P4 shows it, extend the snapshot with one more proxy read at the end.
- **Simulator.** XCUITest can press and drag on space by coordinate in the existing harness: `Driver.point(x, y)`
  is an `XCUICoordinate`, `position(of: .space)` gives the key, and `press(forDuration:thenDragTo:)` holds then
  drags in a straight line (a rising finger is a diagonal target). The drag scenarios are sprint 004's.

Phone checks the tower still owes (`space-trackpad.md` P3 to P5): drag left across the keyboard while the thumb
rises, the cursor never stops; slow drags are precise and a flick reaches about 40 characters; Korean and English
feel equally fast on screen; `안녕` with no space, hold space, one step left gives `안|녕` with nothing lost.
