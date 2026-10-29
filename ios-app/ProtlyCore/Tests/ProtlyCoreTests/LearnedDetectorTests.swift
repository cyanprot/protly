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
}
