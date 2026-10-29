import XCTest
@testable import ProtlyCore

final class HangulTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] {
        // Uppercase letter = manual shift (Dubeolsik double consonant or ㅒ/ㅖ).
        s.map { $0.isUppercase ? KeyEvent(Character($0.lowercased()), .manual) : KeyEvent($0) }
    }

    private func compose(_ s: String) -> String { Hangul.compose(keys(s)).text }

    func testBasicSyllables() {
        XCTAssertEqual(compose("dkssud"), "안녕")
        XCTAssertEqual(compose("gksrmf"), "한글")
        XCTAssertEqual(compose("dml"), "의")
    }

    func testFinalMovesToNextSyllable() {
        XCTAssertEqual(compose("rkrtl"), "각시")   // ㄱ+ㅅ would be ㄳ, the vowel takes ㅅ back
        XCTAssertEqual(compose("dlfrdj"), "읽어")  // ㄺ splits, ㄱ stays, ㅇ starts 어
        XCTAssertEqual(compose("djqtdj"), "없어")
        XCTAssertEqual(compose("rkqt"), "값")
    }

    func testCompoundVowels() {
        XCTAssertEqual(compose("rhk"), "과")
        XCTAssertEqual(compose("dnjs"), "원")
        XCTAssertEqual(compose("ehho"), "도ㅙ")      // ㅗ after a finished 도 starts a lone vowel; ㅗ+ㅐ = ㅙ
    }

    func testManualShiftGivesDoubleConsonant() {
        XCTAssertEqual(compose("Rk"), "까")
        XCTAssertEqual(compose("goTdj"), "했어")
        XCTAssertEqual(compose("dO"), "얘")
    }

    func testAutomaticShiftIsIgnoredInKorean() {
        let k = [KeyEvent("q", .automatic), KeyEvent("k")]
        XCTAssertEqual(Hangul.compose(k).text, "바")
        XCTAssertEqual(Dubeolsik.latin(k), "Qk")
    }

    func testBackspaceIsDropLastKey() {
        XCTAssertEqual(compose(String("rkr".dropLast())), "가")
        XCTAssertEqual(compose(String("rhk".dropLast())), "고")
        XCTAssertEqual(compose(String("dkssu".dropLast())), "안ㄴ")
    }

    func testValidity() {
        XCTAssertTrue(Hangul.compose(keys("dkssud")).isValid)
        XCTAssertTrue(Hangul.compose(keys("zzz")).isValid)          // ㅋㅋㅋ
        XCTAssertTrue(Hangul.compose(keys("whgdkzz")).isValid)      // 좋아ㅋㅋ
        XCTAssertTrue(Hangul.compose(keys("dkss")).isValid)         // 안ㄴ while typing
        XCTAssertFalse(Hangul.compose(keys("hello")).isValid)       // ㅗ first
        XCTAssertFalse(Hangul.compose(keys("ok")).isValid)          // ㅐㅏ
        XCTAssertTrue(Hangul.compose(keys("whgdkbb")).isValid)      // 좋아ㅠㅠ
    }

    func testNonLetterKeyIsInvalidNotACrash() {
        let digit = Hangul.compose([KeyEvent("d"), KeyEvent("k"), KeyEvent("1")])
        XCTAssertFalse(digit.isValid)
        XCTAssertEqual(digit.text, "아1")
        XCTAssertNil(Dubeolsik.jamo(for: KeyEvent("1")))
    }

    func testUppercaseLetterIsManualShift() {
        // Caps lock can hand over "R": stored as "r" + manual shift, so it composes like shift+r.
        let k = KeyEvent("R")
        XCTAssertEqual(k.letter, "r")
        XCTAssertEqual(k.shift, .manual)
        XCTAssertEqual(KeyEvent("Q", .automatic).shift, .automatic)
        XCTAssertEqual(Hangul.compose([KeyEvent("R"), KeyEvent("K")]).text, "까")
        XCTAssertEqual(Dubeolsik.latin([KeyEvent("O"), KeyEvent("K")]), "OK")
    }

    func testJamoThatCannotLeadASyllableIsInvalidNotACrash() {
        let compound = Hangul.compose(jamos: ["ㄳ", "ㅏ"])
        XCTAssertEqual(compound.text, "ㄳㅏ")
        XCTAssertFalse(compound.isValid)
        let latin = Hangul.compose(jamos: ["a", "ㅏ"])
        XCTAssertEqual(latin.text, "aㅏ")
        XCTAssertFalse(latin.isValid)
        XCTAssertFalse(Hangul.compose(jamos: ["ㄱ", "ㅏ", "a"]).isValid)
    }
}
