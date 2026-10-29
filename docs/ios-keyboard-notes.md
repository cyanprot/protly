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
- **Measured:** both lists add about 11 MB RSS. `decide(complete: false)` took about 58 us on a 1-key prefix
  and about 3 us on a longer one while it scanned up to 5,000 prefix matches; with `WordList.hasPrefix` (one
  binary search) it is about 1.1-1.5 us on a 1-key prefix and 3-5 us on 4-5 keys (release, laptop, 2026-10-28).
