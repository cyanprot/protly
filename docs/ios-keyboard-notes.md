# protly iOS keyboard notes

Findings recorded while building the keyboard. Each sprint appends its own section.

## Sprint 1: detector

Measured 2026-10-28 with `swift run -c release --package-path ios-app/ProtlyCore protly-eval ios-app/ProtlyCore/Corpus`
(Swift 6.4.1, Linux). Word lists: FrequencyWords 2018 `en_50k` / `ko_50k`. Corpus: `Corpus/chat.txt` (25 lines,
written for this project), `Corpus/tatoeba-kor.txt` (1,993 lines, every 8th Korean sentence),
`Corpus/tatoeba-eng.txt` (2,266 lines, every 900th English sentence), sampled by `scripts/make-corpus.sh`.

"Switch" = words whose shown language changes at least once while the keys are typed one by one.

### Accuracy by prior bonus

| priorBonus | File | Language | Words | Accuracy | Words that switch while typing |
|---|---|---|---|---|---|
| 0.0 | chat | korean | 60 | 98.33% | 21.7% |
| 0.0 | chat | english | 14 | 92.86% | 42.9% |
| 0.0 | tatoeba-eng | english | 16544 | 99.35% | 1.1% |
| 0.0 | tatoeba-kor | korean | 8626 | 99.59% | 1.0% |
| 0.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| 1.0 | chat | korean | 60 | 98.33% | 21.7% |
| 1.0 | chat | english | 14 | 100.00% | 35.7% |
| 1.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 1.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 1.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| **2.0** | chat | korean | 60 | **98.33%** | 21.7% |
| **2.0** | chat | english | 14 | **100.00%** | 35.7% |
| **2.0** | tatoeba-eng | english | 16544 | **99.55%** | 0.8% |
| **2.0** | tatoeba-kor | korean | 8626 | **99.83%** | 0.5% |
| **2.0** | tatoeba-kor | english | 5 | **100.00%** | 40.0% |
| 3.0 | chat | korean | 60 | 98.33% | 21.7% |
| 3.0 | chat | english | 14 | 100.00% | 35.7% |
| 3.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 3.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 3.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |
| 4.0 | chat | korean | 60 | 98.33% | 21.7% |
| 4.0 | chat | english | 14 | 100.00% | 35.7% |
| 4.0 | tatoeba-eng | english | 16544 | 99.55% | 0.8% |
| 4.0 | tatoeba-kor | korean | 8626 | 99.83% | 0.5% |
| 4.0 | tatoeba-kor | english | 5 | 100.00% | 40.0% |

From 1.0 upward the accuracy is flat; only the order of tied error words changes between runs (dictionary
iteration order).

### Top error words

- priorBonus 0.0: Korean 해x19 꽤x6 새x4 걔x4 뜰x1 도x1 (tatoeba-kor), 걔x1 (chat); English Zirix44 sox31
  Rimax16 (tatoeba-eng), sox1 (chat). Without a prior, 해 (`go`) and "so" (ㄴㅐ = 내) lose to the other list.
- priorBonus 2.0: Korean 꽤x6 걔x4 새x4 뜰x1 (tatoeba-kor), 걔x1 (chat); English Zirix44 Rimax16 glaivex1
  diddlesx1 vibratedx1 Sorosx1 clarifiesx1 Skruax1 (tatoeba-eng). The English errors are names and rare words
  missing from `en_50k` that happen to compose into valid Hangul; the Korean errors are short syllables whose keys
  also spell an English list word (꽤 = keys `Rho` -> "rho", 걔 = `rO` -> "ro", 새 = `to` -> "to",
  뜰 = `Emf` -> "emf").

Chat switching is high by nature: those are the words where the user changes language, and they settle within
1-3 keys (one key cannot tell "r" from ㄱ). `FLIPS=1` before the command prints each switching word with its
per-key trace.

### Decision

**priorBonus 2.0** (the `LanguageDetector` default). It clears the Sprint 1 contract: tatoeba-kor 99.83%
(>= 99.5%), tatoeba-eng 99.55% (>= 99.3%), chat korean 98.33% (>= 98%).
