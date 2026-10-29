import Foundation
import XCTest
@testable import ProtlyCore

// The keyboard only feeds a-z keys today, but KeyEvent, Hangul, TypingSession and the detector are public:
// no key, however odd, may trap, and every edit must stay consistent with what is in the field.
final class UnicodeRobustnessTests: XCTestCase {
    func testShiftedLetterWithMultiCharacterUppercaseDoesNotTrap() {
        // "ß".uppercased() is "SS": two Characters, which Character(_:) cannot hold.
        XCTAssertEqual(Dubeolsik.latin([KeyEvent("ß", .manual)]), "SS")
        XCTAssertEqual(Dubeolsik.latin([KeyEvent("a"), KeyEvent("ﬁ", .automatic)]), "aFI")
        var s = TypingSession()
        XCTAssertEqual(s.type(KeyEvent("ß", .manual)), .mark("SS"))
        XCTAssertEqual(s.commit(), .commit("SS"))
    }

    func testCompoundFinalPassedThroughThenVowelDoesNotTrap() {
        // ㄳ is a final but cannot lead a syllable: a vowel after it must not move it into the lead.
        for compound in "ㄳㄵㄶㄺㄻㄼㄽㄾㄿㅀㅄ" {
            let keys = [KeyEvent("r"), KeyEvent("k"), KeyEvent(compound), KeyEvent("k")]
            let c = Hangul.compose(keys)
            XCTAssertEqual(c.text, "가\(compound)ㅏ")
            XCTAssertFalse(c.isValid)
        }
    }

    func testKoreanDraftInAnyFormGoesToTranslate() {
        // Text copied from a Mac file name is decomposed (NFD): conjoining jamo, no precomposed syllable.
        let nfd = "안녕하세요".decomposedStringWithCanonicalMapping
        XCTAssertFalse(nfd.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) })
        XCTAssertEqual(ActionAPI.mode(forDraft: nfd), .out)
        XCTAssertEqual(ActionAPI.mode(forDraft: "\u{FFA1}\u{FFC2}"), .out)  // halfwidth ㄱㅏ
        XCTAssertEqual(ActionAPI.mode(forDraft: "\u{A960}"), .out)  // jamo extended-A
        XCTAssertEqual(ActionAPI.mode(forDraft: "café, naïve, 日本語"), .fix)
    }
}
