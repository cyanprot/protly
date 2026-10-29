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
}
