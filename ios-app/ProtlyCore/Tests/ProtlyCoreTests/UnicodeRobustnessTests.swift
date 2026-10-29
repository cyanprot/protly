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
}
