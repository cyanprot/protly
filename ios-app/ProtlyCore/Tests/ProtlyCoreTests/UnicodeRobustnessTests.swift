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

    // Scalars a key could carry if a future keycap passed through: emoji, ZWJ sequences, flags, combining
    // marks, bidi controls, zero-width, NUL, newline, CJK, Hangul in every form, digits and symbols.
    static let oddLetters: [Character] = [
        "😀", "👨‍👩‍👧", "🇰🇷", "\u{301}", "\u{200D}", "\u{202E}", "\u{200B}", "\u{FEFF}", "\u{0}", "\n", "\r\n",
        "日", "ㄳ", "ㅘ", "가", "\u{1100}", "\u{FFA1}", "1", "#", " ", "ß", "ﬁ", "İ", "Σ", "ŉ",
    ]
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 1000), ("hi", 800)]),
        korean: WordList(entries: [("dkssud", 50)]),
        priorBonus: 2.0
    )

    func testOddKeysNeverTrapAnywhere() {
        for odd in Self.oddLetters {
            for shift in [Shift.none, .manual, .automatic] {
                let keys = [KeyEvent("r"), KeyEvent("k"), KeyEvent(odd, shift), KeyEvent("k"), KeyEvent(odd, shift)]
                XCTAssertFalse(Hangul.compose(keys).isValid, "\(odd)")
                _ = Dubeolsik.latin(keys)
                _ = Dubeolsik.koreanKeyString(keys)
                for complete in [false, true] {
                    XCTAssertEqual(detector.decide(keys, complete: complete, previous: .korean), .english, "\(odd)")
                }
                var s = TypingSession(detector: detector)
                for k in keys { _ = s.type(k) }
                _ = s.flip()
                XCTAssertNotNil(s.commit())
                _ = s.flip()
                _ = s.backspace()
                s.abandon()
                XCTAssertFalse(s.isComposing)
            }
        }
    }

    func testEditsStayConsistentWithOddKeys() {
        // The flip deletes exactly what the commit inserted plus what was typed after it.
        for odd in Self.oddLetters {
            var s = TypingSession(detector: detector)
            for k in [KeyEvent("h"), KeyEvent(odd), KeyEvent("i")] { _ = s.type(k) }
            guard case .commit(let text)? = s.commit() else { return XCTFail("\(odd)") }
            s.noteInserted(" ")
            guard case let .replace(count, inserted)? = s.flip() else { return XCTFail("\(odd)") }
            XCTAssertEqual(count, (text + " ").count, "\(odd)")
            XCTAssertTrue(inserted.hasSuffix(" "))
            XCTAssertEqual(s.lastTail, inserted)
        }
    }

    func testVeryLongInputComposesAndDecides() {
        // One long run with no space: a single pass over 100k keys.
        let syllable = [KeyEvent("d"), KeyEvent("k"), KeyEvent("s")]  // 안
        let keys = Array(repeating: syllable, count: 33_334).flatMap { $0 }
        let c = Hangul.compose(keys)
        XCTAssertEqual(c.text.count, 33_334)
        XCTAssertTrue(c.isValid)
        XCTAssertEqual(detector.decide(keys, complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys, complete: false, previous: .english), .korean)
        let latin = Array(repeating: KeyEvent("h"), count: 100_000)
        XCTAssertEqual(Dubeolsik.latin(latin).count, 100_000)
        XCTAssertEqual(detector.decide(latin, complete: true, previous: nil), .english)
        XCTAssertNil(KeyEncoder.keys(forHangul: String(repeating: "안녕a", count: 10_000)))
        XCTAssertEqual(KeyEncoder.keys(forHangul: String(repeating: "안녕", count: 10_000))?.count, 60_000)
    }

    func testALongWordTypedKeyByKeyThenUndone() {
        // Each key recomposes the word: hundreds of keys must stay correct. (The cost per key grows with the word: O(n^2) per word.)
        var s = TypingSession(detector: detector)
        let word = Array("dkssudgktpdy")  // 안녕하세요
        for i in 0..<300 { _ = s.type(KeyEvent(word[i % word.count])) }
        XCTAssertEqual(s.keys.count, 300)
        XCTAssertEqual(TypingSession.render(s.keys, as: .korean), String(repeating: "안녕하세요", count: 25))
        var last: FieldEdit?
        while let e = s.backspace() { last = e }
        XCTAssertEqual(last, .mark(""))
        XCTAssertFalse(s.isComposing)
    }

    func testWordListIgnoresOddLines() {
        let text = "the 10\n\n \nbad\nx y z\nn0 abc\n\u{0} 5\n😀 3\nnaïve 2\nGo 7\n안녕 4\n" + String(repeating: "a", count: 10_000) + " 1\n"
        let en = WordList.english(text)
        XCTAssertEqual(en.frequency(of: "the"), 10)
        XCTAssertEqual(en.frequency(of: "go"), 7)
        XCTAssertEqual(en.frequency(of: "naïve"), 0)
        XCTAssertEqual(en.frequency(of: "bad"), 0)
        XCTAssertTrue(en.hasPrefix(String(repeating: "a", count: 9_999)))
        let ko = WordList.korean(text)
        XCTAssertEqual(ko.frequency(of: "dkssud"), 4)
        XCTAssertEqual(ko.count, 1)
        XCTAssertFalse(WordList(entries: []).hasPrefix(""))
        XCTAssertEqual(WordList(entries: []).frequency(of: "x"), 0)
    }
}
