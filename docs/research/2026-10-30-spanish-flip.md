# Why Spanish words flip to Hangul (check 8.5-9o)

Research only, 2026-10-30. No code, test or workflow was changed; every experiment below ran on a copy of
`ios-app/ProtlyCore` outside the repo.

## The failure

`runs/e301e04-15/checks.txt` (branch `ci-shots`), line 17:

```
CHECK 8.5-9o FAIL context="솓" flip context-after-flip="the"
  field="me 둧뭇ㅁ 디 color de tu 촘볃ㅅㅁ, donde la conprastes? jaja "
  want  "me encanta el color de tu chaqueta, donde la conprastes? jaja " center="Translate" want "Polish"
```

The check (`ios-app/CI/UITests/PhoneChecksUITests.swift`, `checks85`) first runs `context(korean: false)`: it
types `the`, which shows `솓` while typed (8.5-8o left Korean as the previous language, and some Korean list key
starts with `the`), taps the left slot to flip it, and types a space. So `the` is committed as English and
`previous == .english`. Then it types the Spanish draft. Any Hangul in the field makes
`ActionAPI.mode(forDraft:)` return `.out`, so the bar center shows Translate instead of Polish.

## Where the decision is made

- `ios-app/ProtlyCore/Sources/ProtlyCore/LanguageDetector.swift`, `decide(_:complete:previous:learned:)`. For a
  finished word (`complete == true`) the rules run in this order:
  1. Keys that do not compose into valid Hangul are English (`Hangul.compose(keys).isValid`).
  2. Chat shorthand: two-consonant abbreviations, one jamo repeated, a manual shift on a doubled-jamo key inside
     the word. All Korean.
  3. `if en == 0, !enLearned { return .korean }`: **unknown in the English list but valid Hangul is Korean.**
  4. `if ko == 0, !koLearned { return .english }`.
  5. Known in both lists: log relative frequency (`count / list total`), plus `priorBonus` 2.0 for the previous
     word's language.

  While typing (`complete == false`) only prefixes matter: no English word starts with the keys and the Hangul is
  valid, so the word is Korean; no Korean word starts with them, so it is English; otherwise the previous language.
- `ios-app/ProtlyCore/Sources/ProtlyCore/Hangul.swift`, `compose`: `isValid` accepts a trailing run of lone
  consonants (and face vowels ㅠ ㅜ ㅡ) after the syllables, because that is what a half-typed Korean word and chat
  look like (안ㄴ, 했ㅋㅋ).
- `ios-app/ProtlyCore/Sources/ProtlyCore/TypingSession.swift`: `type` calls `decide(complete: false)` on every
  key, `commit` calls `decide(complete: true)` and sets `previous` to the committed word's language. That
  `previous` is the prior for the next word.
- `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`: `typeLetter` -> `session.type`, `insertText`
  (space, punctuation) -> `commitWord` -> `session.commit`, then `session.noteInserted`. `refreshField` ->
  `ActionAPI.mode(forDraft:)` picks Translate or Polish.

Design history (`docs/plans/2026-10-28-ios-keyboard.md` Task 1.5, `docs/ios-keyboard-notes.md` "Sprint 1:
detector"): rule 3 exists because "inflected Korean words are mostly not listed" in the 50k subtitle list. Its
known cost was written down in Sprint 1: "The English errors are names and rare words missing from `en_50k` that
happen to compose into valid Hangul" (Zirix x44, Rima x16, glaive, diddles, vibrated). Rule 3 runs before the
prior, so it ignores the previous word's language. Spanish words missing from `en_50k` are the same class of
error, which the English-only corpus never measured.

## Reproduction (failing test)

Swift was not installed in the container. I downloaded the swift.org 6.1.2 Ubuntu 24.04 toolchain into the
session scratchpad. `swift test` on an unchanged copy of the package: 155 tests, 0 failures. Then I added this
file to the copy only (not committed):

```swift
import XCTest
@testable import ProtlyCore

/// 8.5-9o (runs/e301e04-15): a Spanish draft typed on English keys after one committed English word.
final class SpanishFlipTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    /// Feeds the draft the way KeyboardViewController does: letters through `type`, then `commit` and
    /// `noteInserted` for each space or punctuation mark. Returns the field text.
    private func typeDraft(_ s: inout TypingSession, _ text: String) -> String {
        var field = ""
        for ch in text {
            if ch.isASCII, ch.isLetter {
                _ = s.type(KeyEvent(ch))
            } else {
                if case .commit(let w)? = s.commit() { field += w }
                field += String(ch)
                s.noteInserted(String(ch))
            }
        }
        return field
    }

    func testSpanishDraftAfterAnEnglishWordStaysLatin() throws {
        var s = TypingSession(detector: try LanguageDetector.bundled(), previous: .korean)  // 8.5-8o left Korean
        // The check's context step: "the" shows 솓 while typed (previous Korean), the left slot flips it, space.
        for k in keys("the") { _ = s.type(k) }
        XCTAssertEqual(s.flip(), .mark("the"))
        XCTAssertEqual(s.commit(), .commit("the"))
        s.noteInserted(" ")
        s.abandon()  // clearField
        XCTAssertEqual(s.previous, .english)

        let draft = "me encanta el color de tu chaqueta, donde la conprastes? jaja "
        let field = typeDraft(&s, draft)
        XCTAssertEqual(field, draft)
        XCTAssertEqual(ActionAPI.mode(forDraft: field), .fix)
    }

    func testEachSpanishWordAfterEnglishIsEnglish() throws {
        let d = try LanguageDetector.bundled()
        for w in ["encanta", "el", "chaqueta"] {
            XCTAssertEqual(d.decide(keys(w), complete: true, previous: .english), .english, w)
        }
    }
}
```

`swift test --filter SpanishFlipTests` (Swift 6.1.2, Linux):

```
SpanishFlipTests.swift:44: error: testEachSpanishWordAfterEnglishIsEnglish : XCTAssertEqual failed: ("korean") is not equal to ("english") - encanta
SpanishFlipTests.swift:44: error: testEachSpanishWordAfterEnglishIsEnglish : XCTAssertEqual failed: ("korean") is not equal to ("english") - chaqueta
SpanishFlipTests.swift:37: error: testSpanishDraftAfterAnEnglishWordStaysLatin : XCTAssertEqual failed: ("me 둧뭇ㅁ 디 color de tu 촘볃ㅅㅁ, donde la conprastes? jaja ") is not equal to ("me encanta el color de tu chaqueta, donde la conprastes? jaja ")
SpanishFlipTests.swift:38: error: testSpanishDraftAfterAnEnglishWordStaysLatin : XCTAssertEqual failed: ("out") is not equal to ("fix")
```

The field text matches the simulator's character for character. `el` passes on its own after an English word
(second test). It flips in the draft only because `encanta` flipped right before it; see below.

## Root cause

Each word of the draft, with the bundled lists (English total 683,090,613, Korean total 5,164,252; score =
log relative frequency) and the decision for each previous language:

| Word | Hangul reading | Valid | en count (score) | ko count (score) | prev nil / English / Korean | Rule |
|---|---|---|---|---|---|---|
| me | ㅡㄷ | yes | 6,444,985 (-4.66) | 0 | E / E / E | 4 |
| **encanta** | 둧뭇ㅁ | yes | 0 | 0 | **K / K / K** | 3 |
| **el** | 디 | yes | 13,551 (-10.83) | 108 (-10.78) | **K** / E / **K** | 5 |
| color | 채ㅣㅐㄱ | no | 32,837 | 0 | E / E / E | 1 |
| de | ㅇㄷ | yes | 44,903 (-9.63) | 0 | E / E / E | 4 |
| tu | 셔 | yes | 3,368 (-12.22) | 0 | E / E / E | 4 |
| **chaqueta** | 촘볃ㅅㅁ | yes | 0 | 0 | **K / K / K** | 3 |
| donde | 애ㅜㅇㄷ | yes | 281 (-14.70) | 0 | E / E / E | 4 |
| la | ㅣㅁ | no | 52,546 | 0 | E / E / E | 1 |
| conprastes | 채ㅞㄱㅁㄴㅅㄷㄴ | no | 0 | 0 | E / E / E | 1 |
| jaja | ㅓ멈 | no | 0 | 0 | E / E / E | 1 |

- **encanta, chaqueta: rule 3.** Neither word is in `en_50k` (a subtitle list of English), and their keys compose
  into valid Hangul: syllables followed by lone consonants (둧뭇 + ㅁ, 촘볃 + ㅅㅁ), which `isValid` accepts
  because a half-typed Korean word looks the same. They are not in the Korean list either, but rule 3 returns
  Korean before the Korean count or the prior is looked at. The English word just before does not help: the
  prior is only added in rule 5.
- **el: rule 5 plus the chain.** `el` is in both lists (`디` is a Korean subtitle token, 108). Without a prior
  Korean already wins by 0.05; the +2.0 English prior would win it back, but the word before it is `encanta`,
  just committed as Korean, so `previous == .korean` and Korean wins by 2.05. One rule-3 error moves the prior to
  Korean and takes the next ambiguous word with it.
- **Why the others stayed Latin.** `color`, `la`, `conprastes`, `jaja` do not compose into valid Hangul (a lone
  vowel other than ㅠ ㅜ ㅡ, such as ㅐ or ㅣ or ㅓ, outside a syllable): rule 1. `me`, `de`, `tu`, `donde` are valid
  Hangul but in `en_50k` (Spanish shows up in English subtitles) and not in the Korean list: rule 4, which returns
  English before the prior. That is why `donde` stays Latin although it comes right after the Korean-committed
  `chaqueta`.
- While typing, `encanta` shows Latin for 4 keys and Hangul from `encan` on (no English word starts with `encan`);
  `chaqueta` from `chaq`. The flip is visible before the space.

This is not limited to the draft. On the top 10,000 a-z words of FrequencyWords `es_50k` (same source and license
as the bundled lists; downloaded to the scratchpad for this measurement only), decided after an English word:
**1,150 words (11.5%, 8.5% of running tokens) come out Korean**. By branch: 882 are unknown in both lists with a
syllable (fue = 렫, tienes, entonces, sobre, antes), 255 are unknown in both and all lone consonants, because
Spanish `a e s d r t c` are all consonant keys in Dubeolsik (verdad = ㅍㄷㄱㅇㅁㅇ, estar, desde, cada), 12 are in
both lists and Korean wins by frequency even with the English prior (en = 두, dos = 앤, sus = 년, tus = 션, di = 야),
and 1 is only in the Korean list (tos = 샌).

## Fix options

Each option was built in the scratchpad copy behind an environment switch and measured with:

- **Korean after English** (the case the detector exists for): every Korean token of `Corpus/tatoeba-kor.txt` and
  `Corpus/chat.txt` (8,693) decided as if the previous word were English; plus how many of them flicker (shown
  language changes twice or more while typed).
- **Spanish after English**: the 10,000 `es_50k` words above.
- `protly-eval` at priorBonus 2.0 (the numbers in `docs/ios-keyboard-notes.md`), and the full `swift test`.

| Variant | Korean after English | Korean flicker | Spanish words Korean | 8.5-9o draft | chat ko | tatoeba-eng | tatoeba-kor |
|---|---|---|---|---|---|---|---|
| today | 99.15% (74 wrong) | 0.01% | 11.5% | fails | 100% | 99.55% | 99.95% |
| 1: prior on unknown words | **86.22% (1,198 wrong)** | **12.68%** | 0.1% | passes | 98.51% | 100% | 99.93% |
| 2: stray trailing consonant | 99.15% (74) | 0.01% | 5.8% | passes | 100% | 99.67% | 99.95% |
| 2 + consonant-only step | 99.15% (74) | 0.01% | 3.3% | passes | 100% | 99.71% | 99.95% |
| 3: Spanish word list | 99.15% (74) | 0.01% | 0.1% (training data) | passes | 100% | 99.65% | 99.95% |
| also tried: syllable inventory | 98.99% (88) | 0.16% | 6.5% | passes | 98.51% | 99.86% | 99.80% |
| also tried: 2 + same rule while typing | 99.15% (74) | **11.52%** | 3.3% | passes | 100% | 99.71% | 99.95% |

The 74 Korean errors of today are all short known clashes (내 x50 = `so`, 해 x19 = `go`, 새 x4 = `to`, 도 x1)
and are the same in every row except option 1 and the syllable inventory.

**Existing tests:** none of the 155 existing tests fails under options 1, 2, 2 + step or 3 (the two new tests pass
under each). Only "2 + same rule while typing" broke one, `UnicodeRobustnessTests.testVeryLongInputComposesAndDecides`
(line 97). That no test fails under option 1 is itself a finding: the suite does not cover the case option 1
breaks. `LanguageDetectorTests.testUnknownValidHangulIsKorean` checks 했어 after English, but its keys contain a
manual shift (`goTdj`), so the shift rule decides before rule 3 is reached, and ㅋㅋ is decided by the
repeated-jamo rule.

### Option 1: let the prior decide words unknown in both lists

In rule 3, when the word is unknown in both lists, return `previous ?? .korean` instead of `.korean`.

- Fixes the draft and nearly all Spanish (0.1%), and tatoeba-eng goes to 100% (Zirix, Rima, glaive are fixed).
- **Breaks the real case.** An inflected Korean word that is not in `ko_50k` typed right after an English word
  stays English: 1,198 of 8,693 Korean tokens (뭐, 탐은, 톰이랑, 테니스를, 봐, 줘, 뭘; in chat.txt `gym 가는중`
  becomes "gym rksmswnd"), and 12.7% of Korean words flicker while typed (shown Korean, English at the space).
  This is exactly the code-switching rule 3 was written for.
- Tests: no existing test fails, which shows the gap. It would need a new guard test (an unshifted, unlisted
  inflected word after English, e.g. 가는중 or 테니스를 -> Korean), which option 1 then fails. Rule 3 in the
  `LanguageDetector.swift` header comment and the notes tables would change.

### Option 2: a finished Korean word does not end in a stray consonant (recommended)

In rule 3, before returning Korean for a word unknown in both lists: if the composition has at least one syllable
and then a trailing run of lone jamo that is not glue (ㅋ ㅎ ㅠ ㅜ), return English. Commit only (`complete ==
true`); while typing a trailing consonant is normal (안ㄴ). The sketch that was measured:

```swift
// In decide, complete path, inside `if en == 0, !enLearned`:
if ko == 0, !koLearned, Self.endsInStrayConsonant(hangul.text) { return .english }
return .korean

/// A syllable followed by a trailing run of lone jamo that is not glue (ㅋ ㅎ ㅠ ㅜ): 둧뭇ㅁ, 촘볃ㅅㅁ.
static func endsInStrayConsonant(_ text: String) -> Bool {
    let tail = text.reversed().prefix(while: Hangul.isLoneJamo)
    guard !tail.isEmpty, tail.count < text.count else { return false }
    return !tail.allSatisfy { ChatShorthand.glueJamo.contains($0) }
}
```

- encanta and chaqueta commit as English, so `previous` stays English and `el` wins with the prior: the draft is
  all Latin and the center offers Polish.
- No measured cost: Korean after English, Korean flicker, chat and tatoeba-kor are unchanged; tatoeba-eng goes
  from 99.55% to 99.67% (Rima x16 and other rare English words are fixed by the same rule).
- Limits: Spanish after English only drops from 11.5% to 5.8%. Words whose last consonant fits as a final (fue =
  렫, sido = 냐애, visto = 퍈새) and all-consonant words (verdad, estar, desde) still flip. Encanta keeps showing 둧뭇
  while typed and turns Latin at the space. Making the while-typing rule match ("2 + same rule while typing":
  keep the previous language when neither list has the prefix) removes most of that but makes 11.5% of Korean
  words flicker after an English word and breaks one test, so it is not part of this option.
- Optional second step, measured: an all-lone-consonant word unknown in both lists follows the prior (`previous ??
  .korean`). Spanish drops to 3.3% with no corpus cost, but the corpus has no unlisted consonant-only chat
  shorthand typed after English; ㄹㅇㅋㅋ or ㅎㅇㅌ right after an English word would become "fdzz" / "gdx". Only
  with a guard for runs that contain an abbreviation or end in a glue run, and its own tests.
- Tests: no existing test changes. Add: the two tests above; `endsInStrayConsonant` cases (둧뭇ㅁ, 촘볃ㅅㅁ -> true;
  했ㅋㅋ, 앜ㅋ, ㄱㅅ, 안녕 -> false); a guard that `gym 가는중` and 테니스를 after English stay Korean. Update rule 3
  in the `LanguageDetector.swift` header and re-run `protly-eval` for the notes.

### Option 3: a Spanish word list as Latin evidence

Bundle FrequencyWords `es_50k` (same source and CC-BY-SA-4.0 license as the current lists) and, in rule 3, treat a
word unknown in both lists but present in the Spanish list as English (Latin).

- Spanish after English 0.1%, but this is measured on the list's own top 10,000 words, so it is an upper bound;
  real drafts contain misspellings (`conprastes`) and forms outside the top 50k. The 12 Spanish words that beat
  English in rule 5 (en, dos, sus, tus) still flip. No Korean cost on the corpus (the list is only consulted when
  the Korean list does not know the word).
- Costs: a third 50k list in the keyboard extension. Sprint 1 measured about 11 MB RSS for the two lists and
  136 ms (release, laptop) to load them, so roughly +5 MB and +60 ms against a 40 MB memory limit. It helps
  Spanish only: Portuguese, Italian or French drafts need their own lists. The `missingWords`-style curation and
  the Swift package resources (`Package.swift` of ProtlyCore) change.
- Tests: no existing test fails. Add a list round-trip test like `testKoreanListRoundTrip`, the two tests above,
  and the Korean-after-English guard.

Also measured and dropped: a syllable inventory (a word unknown in both lists is Korean only if every syllable
occurs in some `ko_50k` word; 둧, 촘, 볃 never do). It fixes the draft but loses real Korean with rare syllables
(껌이다, 굵다, 벚나무, 엷은, and 좋아ㅋㅋ because it composes as 좋앜ㅋ), and is weaker than option 2 on Spanish.

## Recommendation

**Option 2** (stray trailing consonant, commit only). It fixes all three words of 8.5-9o (two directly, `el`
through the prior chain), keeps every Korean-after-English number unchanged, improves tatoeba-eng, changes no
existing test and needs no new data. Option 1 must not be used: it removes the rule that lets an unlisted Korean
word be recognised after an English word. Option 3 is the follow-up if Spanish drafting becomes a real use, since
option 2 leaves about 6% of common Spanish words flipping (fue, verdad, estar). Either way, add the
Korean-after-English guard test first: today's suite would not notice if that case broke.

Residuals no option here fixes: `el` at a message start (no prior) is Korean by 0.05 in score (디 108 vs el
13,551), and short words in both lists (en, dos, sus, tus) beat English even with the +2.0 prior. The bar's flip
fixes them one word at a time and teaches the reading.
