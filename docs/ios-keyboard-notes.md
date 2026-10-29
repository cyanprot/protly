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
