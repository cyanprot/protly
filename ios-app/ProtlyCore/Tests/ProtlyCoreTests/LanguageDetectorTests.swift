import XCTest
@testable import ProtlyCore

final class LanguageDetectorTests: XCTestCase {
    // Tiny lists keep these tests about the rules, not about corpus counts.
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 1000), ("go", 500), ("red", 100)]),
        korean: WordList(entries: [("go", 500), ("dkssud", 50)]),  // "go" = 해, "dkssud" = 안녕
        priorBonus: 2.0
    )

    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testInvalidHangulIsEnglish() {
        XCTAssertEqual(detector.decide(keys("hello"), complete: true, previous: .korean), .english)
    }

    func testKnownOnlyInOneList() {
        XCTAssertEqual(detector.decide(keys("dkssud"), complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys("the"), complete: true, previous: .korean), .english)  // 솓
        XCTAssertEqual(detector.decide(keys("red"), complete: true, previous: nil), .english)      // ㄱㄷㅇ
    }

    func testUnknownValidHangulIsKorean() {
        let k = [KeyEvent("g"), KeyEvent("o"), KeyEvent("t", .manual), KeyEvent("d"), KeyEvent("j")]  // 했어
        XCTAssertEqual(detector.decide(k, complete: true, previous: .english), .korean)
        XCTAssertEqual(detector.decide(keys("zz"), complete: true, previous: nil), .korean)        // ㅋㅋ
    }

    func testRepeatedJamoIsKoreanEvenWhenEnglishKnowsIt() {
        // English subtitles contain "dd", "bb", "zz": the repeated-jamo rule must win anyway.
        let d = LanguageDetector(
            english: WordList(entries: [("dd", 900), ("bb", 900), ("zz", 900), ("rr", 900)]),
            korean: WordList(entries: [("dkssud", 50)]),
            priorBonus: 2.0
        )
        for w in ["zz", "dd", "bb", "rr", "zzz"] {  // ㅋㅋ ㅇㅇ ㅠㅠ ㄱㄱ ㅋㅋㅋ
            for prev in [nil, Language.english, .korean] {
                XCTAssertEqual(d.decide(keys(w), complete: true, previous: prev), .korean, "\(w) prev \(String(describing: prev))")
            }
        }
    }

    func testPriorBreaksCloseCalls() {
        // go: 500/1600 in English vs 500/550 in Korean. Korean wins alone; the English prior flips it.
        XCTAssertEqual(detector.decide(keys("go"), complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys("go"), complete: true, previous: .english), .english)
    }

    func testPrefixWhileTyping() {
        XCTAssertEqual(detector.decide(keys("th"), complete: false, previous: nil), .english)   // only "the"
        XCTAssertEqual(detector.decide(keys("dkss"), complete: false, previous: nil), .korean)  // 안ㄴ -> 안녕
        // "g" fits English "go" and Korean ㅎ: keep the previous language, Korean at a message start.
        XCTAssertEqual(detector.decide(keys("g"), complete: false, previous: .english), .english)
        XCTAssertEqual(detector.decide(keys("g"), complete: false, previous: nil), .korean)
    }

    func testAutoShiftKeepsEnglishLookup() {
        let k = [KeyEvent("t", .automatic), KeyEvent("h"), KeyEvent("e")]
        XCTAssertEqual(detector.decide(k, complete: true, previous: nil), .english)
        XCTAssertEqual(detector.render(k, as: .english), "The")
        XCTAssertEqual(detector.render(k, as: .korean), "솓")
    }

    func testNonLetterKeyIsEnglish() {
        let k = [KeyEvent("d"), KeyEvent("k"), KeyEvent("1")]
        XCTAssertEqual(detector.decide(k, complete: false, previous: .korean), .english)
        XCTAssertEqual(detector.decide(k, complete: true, previous: .korean), .english)
    }

    func testHasPrefix() {
        let list = WordList(entries: [("go", 1), ("the", 1)])
        XCTAssertTrue(list.hasPrefix("th"))
        XCTAssertTrue(list.hasPrefix("go"))
        XCTAssertFalse(list.hasPrefix("goo"))
        XCTAssertFalse(list.hasPrefix("x"))
        XCTAssertFalse(list.hasPrefix("zzz"))  // past the end
    }

    func testUnlistedUnshiftedKoreanAfterEnglishIsKorean() {
        // Rule 3 without the shift rule (testUnknownValidHangulIsKorean's 했어 is decided by the shift).
        for w in ["rksmswnd", "xpsltmfmf"] {  // 가는중, 테니스를: in neither list, no shifted key
            XCTAssertEqual(detector.decide(keys(w), complete: true, previous: .english), .korean, w)
        }
    }

    func testStrayTrailingConsonantOnCommitIsEnglish() {
        // Spanish encanta = 둧뭇ㅁ, chaqueta = 촘볃ㅅㅁ: in neither list, a finished Korean word does not end so.
        for w in ["encanta", "chaqueta"] {
            for prev in [nil, Language.english, .korean] {
                XCTAssertEqual(detector.decide(keys(w), complete: true, previous: prev), .english,
                               "\(w) prev \(String(describing: prev))")
            }
        }
    }

    func testStrayTrailingConsonantWhileTypingStaysKorean() {
        // Commit only: while typing, encanta shows Hangul from "encan" on (no English word starts with it).
        XCTAssertEqual(detector.decide(keys("encanta"), complete: false, previous: .english), .korean)
    }

    func testGlueTailAfterEnglishStaysKorean() {
        for w in ["dkzz", "qorhvkbb"] {  // 앜ㅋ (glue), 배고파ㅠㅠ (a vowel run): chat, not a stray
            XCTAssertEqual(detector.decide(keys(w), complete: true, previous: .english), .korean, w)
        }
    }

    func testEndsInStrayConsonant() {
        for t in ["둧뭇ㅁ", "촘볃ㅅㅁ"] { XCTAssertTrue(LanguageDetector.endsInStrayConsonant(t), t) }
        for t in ["했ㅋㅋ", "앜ㅋ", "ㄱㅅ", "안녕"] { XCTAssertFalse(LanguageDetector.endsInStrayConsonant(t), t) }
    }

    func testChatShorthandTailIsNotStray() {
        // As composed: 좋아ㅇㅇ = 좋앙ㅇ and 가자ㄱㄱ = 가작ㄱ (the run's first jamo became the final).
        for t in ["대박ㄹㅇ", "응ㅇㅇ", "아니ㅡㅡ", "헐ㄷㄷ", "넵ㄱㅅ", "좋앙ㅇ", "왜ㅡㅡ", "가작ㄱ", "대박ㄹㅇㅋㅋ"] {
            XCTAssertFalse(LanguageDetector.endsInStrayConsonant(t), t)
        }
        // The run's first jamo joined a double final: 미안ㅈㅅ = 미앉ㅅ (ㄵ), 헐ㅁㅊ = 헒ㅊ (ㄻ), 넵ㅅㄱ = 넶ㄱ (ㅄ).
        // 몰라ㅁㄹ = 몰람ㄹ has a single final.
        for t in ["미앉ㅅ", "헒ㅊ", "넶ㄱ", "몰람ㄹ"] {
            XCTAssertFalse(LanguageDetector.endsInStrayConsonant(t), t)
        }
        // An abbreviation that ends in glue (생일ㅊㅋ, 굿ㅇㅋ), and runs of several units.
        for t in ["생일ㅊㅋ", "굿ㅇㅋ", "넵ㄱㅅㄱㅅ", "대박ㅋㅋㄹㅇ", "무섭ㅎㄷㄷ"] {
            XCTAssertFalse(LanguageDetector.endsInStrayConsonant(t), t)
        }
        XCTAssertFalse(LanguageDetector.endsInStrayConsonant("ㅂㄷㅂㄷ"))  // no syllable: not a word ending
    }

    func testStrayRuleNeedsTheWordUnknownInKorean() {
        // Listed or learned as Korean, the same keys stay Korean: a flip to Korean teaches the word.
        let listed = LanguageDetector(english: WordList(entries: [("the", 1000)]),
                                      korean: WordList(entries: [("encanta", 10)]), priorBonus: 2.0)
        XCTAssertEqual(listed.decide(keys("encanta"), complete: true, previous: .english), .korean)
        var l = LearnedWords()
        l.learn("둧뭇ㅁ", as: .korean)
        XCTAssertEqual(detector.decide(keys("encanta"), complete: true, previous: .english, learned: l), .korean)
    }
}

/// The bundled 50k lists, for cases that depend on what the real lists do and do not contain.
final class LanguageDetectorBundledTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    /// Feeds a draft the way KeyboardViewController does: letters through `type`, then `commit` and
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

    /// Korean after English: an inflected word missing from ko_50k stays Korean (chat.txt, spanish-flip.md).
    func testUnlistedKoreanAfterAnEnglishWordStaysKorean() throws {
        let d = try LanguageDetector.bundled()
        for w in ["rksmswnd", "xpsltmfmf"] {  // 가는중, 테니스를
            XCTAssertEqual(d.decide(keys(w), complete: true, previous: .english), .korean, w)
        }
        var s = TypingSession(detector: d, previous: .english)
        XCTAssertEqual(typeDraft(&s, "gym rksmswnd "), "gym 가는중 ")
        var t = TypingSession(detector: d, previous: .english)
        XCTAssertEqual(typeDraft(&t, "the xpsltmfmf "), "the 테니스를 ")
    }

    /// 8.5-9o (runs/e301e04-15): a Spanish draft typed on English keys after one committed English word.
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

    /// Korean chat must not regress for the Spanish fix: words ending in shorthand stay Korean on commit
    /// after either language. The first list flipped to English under the first cut of the stray rule.
    func testChatShorthandEndingsStayKorean() throws {
        let d = try LanguageDetector.bundled()
        let words = ["대박ㄹㅇ", "응ㅇㅇ", "아니ㅡㅡ", "헐ㄷㄷ", "넵ㄱㅅ", "좋아ㅇㅇ", "왜ㅡㅡ", "가자ㄱㄱ",
                     "진짜ㄹㅇ", "아ㅇㅋ", "오키ㅇㅋ", "감사ㅎㅎ", "미친ㅅㄲ", "배고파ㅠㅠ", "했ㅋㅋ", "고마워ㄳ",
                     "ㄹㅇ", "ㅇㅇ", "ㄱㄱ", "대박ㄹㅇㅋㅋ", "미안ㅈㅅ", "헐ㅁㅊ", "몰라ㅁㄹ", "넵ㅅㄱ",
                     // Unshifted, so rule 3 decides them: the final+run path, the abbreviation sets, a lone
                     // vowel, an abbreviation ending in glue, runs of several units.
                     "콜ㄱㄱ", "그래ㄹㅇ", "맞아ㄹㅇ", "나도ㅇㅈ", "그래ㄹㅇㅋㅋ", "와ㅁㅊ", "잠만ㄱㄷ", "왜ㅡ",
                     "생일ㅊㅋ", "굿ㅇㅋ", "생일ㅊㅋㅊㅋ", "넵ㄱㅅㄱㅅ", "대박ㅋㅋㄹㅇ", "무섭ㅎㄷㄷ"]
        for w in words {
            let k = try XCTUnwrap(KeyEncoder.keys(forHangul: w), w)
            for prev in [Language.english, .korean] {
                XCTAssertEqual(d.decide(k, complete: true, previous: prev), .korean, "\(w) prev \(prev)")
            }
        }
    }

    func testEachSpanishWordAfterEnglishIsEnglish() throws {
        let d = try LanguageDetector.bundled()
        for w in ["encanta", "el", "chaqueta"] {
            XCTAssertEqual(d.decide(keys(w), complete: true, previous: .english), .english, w)
        }
    }
}
