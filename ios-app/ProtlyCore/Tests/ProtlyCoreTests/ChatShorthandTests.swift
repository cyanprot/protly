import XCTest
@testable import ProtlyCore

final class ChatShorthandTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testGluedShorthandIsValidHangul() {
        // 아+ㅋㅋ typed in one go is 앜ㅋ (ㅋ becomes the final), like Apple's keyboard: not tested here.
        for (k, text) in [("zzwlsWk", "ㅋㅋ진짜"), ("bbskeh", "ㅠㅠ나도"),
                          ("dzdkfrpTdj", "ㅇㅋ알겠어"), ("ggrhakdnj", "ㅎㅎ고마워")] {
            let c = Hangul.compose(k.map { KeyEvent($0) })  // "W", "T" = manual shift
            XCTAssertEqual(c.text, text)
            XCTAssertTrue(c.isValid, text)
        }
    }

    func testOtherLoneJamoBeforeASyllableStaysInvalid() {
        XCTAssertFalse(Hangul.compose(keys("rdkssud")).isValid)   // ㄱ안녕: one lone ㄱ is no glue
        XCTAssertFalse(Hangul.compose(keys("ffdk")).isValid)      // ㄹㄹ아: ㄹ is not a glue jamo
        XCTAssertFalse(Hangul.compose(keys("strong")).isValid)    // ㄴㅅ개ㅜㅎ
        XCTAssertFalse(Hangul.compose(keys("llama")).isValid)     // ㅣㅣ마: ㅣ is not a glue jamo
    }

    func testGlueRunStartingAsAFinalIsValid() {
        // Typed in one go, the first ㅋ/ㅎ becomes the vowel syllable's final: 그랰ㅋ좋아, 핳ㅎ고마워.
        XCTAssertEqual(Hangul.compose(keys("rmfozzwhgdk")), Composition(text: "그랰ㅋ좋아", isValid: true))
        XCTAssertEqual(Hangul.compose(keys("gkggrhakdnj")), Composition(text: "핳ㅎ고마워", isValid: true))
        XCTAssertFalse(Hangul.compose(keys("rmfozgwhgdk")).isValid)  // 그랰ㅎ좋아: the final is not the run's jamo
    }
}

final class ShorthandDetectorTests: XCTestCase {
    // English knows the keys of both abbreviations; Korean knows neither.
    let d = LanguageDetector(
        english: WordList(entries: [("rt", 900), ("gd", 900), ("re", 900), ("the", 1000)]),
        korean: WordList(entries: [("dkssud", 50)]),
        priorBonus: 2.0
    )
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testAbbreviationsAreKorean() {
        for w in ["rt", "gd"] {  // ㄱㅅ ㅎㅇ
            for prev in [nil, Language.english, .korean] {
                XCTAssertEqual(d.decide(keys(w), complete: true, previous: prev), .korean, w)
            }
        }
    }

    func testRealEnglishPairStaysEnglish() {
        XCTAssertEqual(d.decide(keys("re"), complete: true, previous: .english), .english)  // ㄱㄷ left out
    }

    func testGluedShorthandIsKorean() {
        let k = [KeyEvent("z"), KeyEvent("z"), KeyEvent("w"), KeyEvent("l"), KeyEvent("s"), KeyEvent("w", .manual), KeyEvent("k")]
        XCTAssertEqual(d.decide(k, complete: true, previous: .english), .korean)  // ㅋㅋ진짜
    }
}
