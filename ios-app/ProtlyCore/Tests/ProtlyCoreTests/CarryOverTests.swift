import XCTest
@testable import ProtlyCore

final class CarryOverTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }  // uppercase = manual shift

    func testShiftInsideAWordIsKorean() {
        let d = LanguageDetector(
            english: WordList(entries: [("ro", 900), ("got", 900), ("do", 900)]),
            korean: WordList(entries: [("dkssud", 50)]),
            priorBonus: 2.0
        )
        for w in ["rO", "dO", "goT"] {  // 걔 얘 했
            for complete in [true, false] {
                XCTAssertEqual(d.decide(keys(w), complete: complete, previous: .english), .korean, w)
            }
        }
        XCTAssertEqual(d.decide(keys("RO"), complete: true, previous: .english), .english)  // caps lock: 꺠 is not meant
    }

    func testMissingWordsJoinTheKoreanList() {
        let list = WordList.korean("", adding: [("걍", 400)])
        XCTAssertEqual(list.frequency(of: "rid"), 400)
    }

    func testBundledListsDecideTheCarryOvers() throws {
        let d = try LanguageDetector.bundled()
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: .korean), .korean)   // 걍
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: nil), .korean)
        XCTAssertEqual(d.decide(keys("rid"), complete: true, previous: .english), .english) // get rid of
        XCTAssertEqual(d.decide(keys("rO"), complete: true, previous: .english), .korean)   // 걔
        XCTAssertEqual(d.decide(keys("Rho"), complete: true, previous: .korean), .korean)   // 꽤
    }
}
