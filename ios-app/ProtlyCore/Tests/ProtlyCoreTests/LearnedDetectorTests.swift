import XCTest
@testable import ProtlyCore

final class LearnedDetectorTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testLearnedWordFeedsTheDetector() {
        // Relative frequencies like the real lists: "rid" 64 per million, 걍 missing from Korean.
        let d = LanguageDetector(
            english: WordList(entries: [("the", 999_936), ("rid", 64)]),
            korean: WordList(entries: [("dkssud", 1_000)]),
            priorBonus: 2.0
        )
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: .korean), .english)
        var l = LearnedWords()
        l.learn("걍", as: .korean)
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: .korean, learned: l), .korean)
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: nil, learned: l), .korean)
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: .english, learned: l), .english)
        // While typing, a learned Korean word keeps ㄱㅑ Korean after a Korean word.
        XCTAssertEqual(d.decide(keys("ri"), complete: false, previous: .korean), .english)
        XCTAssertEqual(d.decide(keys("ri"), complete: false, previous: .korean, learned: l), .korean)
    }

    func testOneFlipCannotTakeACommonWord() {
        // "go" and 해 at their real relative frequencies (FrequencyWords 2018).
        let d = LanguageDetector(
            english: WordList(entries: [("go", 2_500_000), ("the", 722_500_000)]),
            korean: WordList(entries: [("go", 13_611), ("rmfo", 5_168_389)]),
            priorBonus: 2.0
        )
        var l = LearnedWords()
        l.learn("go", as: .english)
        l.learn("해", as: .korean)
        XCTAssertEqual(d.decide(keys("go"), complete: true, previous: .korean, learned: l), .korean)
        XCTAssertEqual(d.decide(keys("go"), complete: true, previous: .english, learned: l), .english)
    }
    func testLearnedEnglishWordFeedsTheDetector() {
        // 안녕 is listed in Korean but rare; dkssud is not English until taught.
        let d = LanguageDetector(
            english: WordList(entries: [("the", 1_000_000)]),
            korean: WordList(entries: [("dkssud", 1), ("rmfo", 999_999)]),
            priorBonus: 2.0
        )
        var l = LearnedWords()
        l.learn("dkssud", as: .english)
        XCTAssertEqual(d.decide(keys("dkssud"), complete: true, previous: nil), .korean)
        XCTAssertEqual(d.decide(keys("dkssud"), complete: true, previous: nil, learned: l), .english)
        XCTAssertEqual(d.decide(keys("dkssud"), complete: false, previous: .english), .korean)
        XCTAssertEqual(d.decide(keys("dkssud"), complete: false, previous: .english, learned: l), .english)
        // Missing from both lists: only the learned English word keeps it from the Hangul default.
        let empty = LanguageDetector(english: WordList(entries: [("the", 1)]), korean: WordList(entries: [("rmfo", 1)]))
        for complete in [true, false] {
            XCTAssertEqual(empty.decide(keys("dkssud"), complete: complete, previous: nil), .korean)
            XCTAssertEqual(empty.decide(keys("dkssud"), complete: complete, previous: nil, learned: l), .english)
        }
    }

    func testLearnedEnglishWordIsReadByItsEnglishKey() {
        // Manual shift on the first key: English key "rkt", Korean key "Rkt" (깟). Taught as English "rkt".
        let d = LanguageDetector(english: WordList(entries: [("the", 1)]), korean: WordList(entries: [("rmfo", 1)]))
        var l = LearnedWords()
        l.learn("Rkt", as: .english)
        for complete in [true, false] {
            XCTAssertEqual(d.decide(keys("Rkt"), complete: complete, previous: nil), .korean)
            XCTAssertEqual(d.decide(keys("Rkt"), complete: complete, previous: nil, learned: l), .english)
        }
        // And a Korean word taught by its Korean key does not leak to English: 깟 learned is still Korean.
        var k = LearnedWords()
        k.learn("깟", as: .korean)
        for complete in [true, false] {
            XCTAssertEqual(d.decide(keys("Rkt"), complete: complete, previous: nil, learned: k), .korean)
        }
    }
}
