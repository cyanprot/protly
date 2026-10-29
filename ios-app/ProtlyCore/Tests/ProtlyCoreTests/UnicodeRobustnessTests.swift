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
        // Hangul fillers are invisible: Instagram users paste them as blank names and spacers. Not Korean.
        for filler in ["\u{115F}", "\u{1160}", "\u{3164}", "\u{FFA0}"] {
            XCTAssertEqual(ActionAPI.mode(forDraft: "see you" + filler), .fix, filler.debugDescription)
        }
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
        // No trap, and the flip replaces exactly the tail it reports (joined characters: testFlipDeletesExactlyTheTailInTheField).
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
        // One long run with no space: a single pass over 15k-20k keys.
        let syllable = [KeyEvent("d"), KeyEvent("k"), KeyEvent("s")]  // 안
        let keys = Array(repeating: syllable, count: 5_000).flatMap { $0 }
        let c = Hangul.compose(keys)
        XCTAssertEqual(c.text.count, 5_000)
        XCTAssertTrue(c.isValid)
        XCTAssertEqual(detector.decide(keys, complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys, complete: false, previous: .english), .korean)
        let latin = Array(repeating: KeyEvent("h"), count: 20_000)
        XCTAssertEqual(Dubeolsik.latin(latin).count, 20_000)
        XCTAssertEqual(detector.decide(latin, complete: true, previous: nil), .english)
        XCTAssertNil(KeyEncoder.keys(forHangul: String(repeating: "안녕a", count: 2_000)))
        XCTAssertEqual(KeyEncoder.keys(forHangul: String(repeating: "안녕", count: 2_000))?.count, 12_000)
    }

    func testALongWordTypedKeyByKeyThenUndone() {
        // Each key recomposes the word: hundreds of keys must stay correct. (The cost per key grows with the word: O(n^2) per word.)
        var s = TypingSession(detector: detector)
        let word = Array("dkssudgktpdy")  // 안녕하세요
        for i in 0..<120 { _ = s.type(KeyEvent(word[i % word.count])) }
        XCTAssertEqual(s.keys.count, 120)
        XCTAssertEqual(TypingSession.render(s.keys, as: .korean), String(repeating: "안녕하세요", count: 10))
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

    func testFlipDeletesExactlyTheTailInTheField() {
        // In the field the word and what follows it sit together, and can join into one character
        // (a combining mark, a final jamo, the second half of a flag): the flip deletes the joined count.
        // Since Q5 only spaces follow a flippable word; a joining insert ends the flip instead.
        let cases: [(String, String)] = [("gi", "\u{301}"), ("rk", "\u{11A8}"), ("gi", "\u{FE0F}"), ("gi", " "), ("gi", " 😀")]
        for (word, after) in cases {
            guard after.allSatisfy({ $0 == " " }) else {
                var s = TypingSession()
                for c in word { _ = s.type(KeyEvent(c)) }
                _ = s.commit()
                s.noteInserted(after)
                XCTAssertNil(s.lastTail, word + after)
                XCTAssertNil(s.flip(), word + after)
                continue
            }
            var s = TypingSession()
            for c in word { _ = s.type(KeyEvent(c)) }
            _ = s.commit()
            s.noteInserted(after)
            let tail = s.lastTail!
            guard case let .replace(count, inserted)? = s.flip() else { return XCTFail(word + after) }
            XCTAssertEqual(count, tail.count, word + after)
            // Field round trip: what is left before the tail never changes.
            var field = "prefix " + tail
            field = String(field.dropLast(count)) + inserted
            XCTAssertTrue(field.hasPrefix("prefix "), word + after)
            XCTAssertEqual(field, "prefix " + inserted)
        }
        var s = TypingSession()
        _ = s.type(KeyEvent("🇰"))
        _ = s.commit()
        s.noteInserted("🇷")  // 🇰🇷 is one character: the flip ends rather than split it
        XCTAssertNil(s.lastTail)
        XCTAssertNil(s.flip())
    }

    func testBackspaceWithNothingComposingEndsTheFlip() {
        // The keyboard deletes normally after a nil backspace: the committed word is no longer at the cursor.
        var s = TypingSession()
        for c in "gi" { _ = s.type(KeyEvent(c)) }
        _ = s.commit()
        s.noteInserted(" ")
        XCTAssertNil(s.backspace())
        XCTAssertNil(s.lastTail)
        XCTAssertNil(s.flip())
    }

    func testWordListCountsNeverOverflow() {
        // Huge counts saturate instead of trapping; negative and zero counts are dropped.
        let max = String(Int.max)
        let a = WordList.english("a \(max)\nb 1\nab \(max)")
        XCTAssertEqual(a.count, 3)
        XCTAssertTrue(a.total.isFinite)
        XCTAssertGreaterThan(a.frequency(of: "a"), a.frequency(of: "b"))
        let merged = WordList.english("a \(max)\nA \(max)\nA 1")  // one key after lowercasing
        XCTAssertEqual(merged.count, 1)
        XCTAssertGreaterThan(merged.frequency(of: "a"), 0)
        XCTAssertEqual(WordList.english("a -5\nb 0").count, 0)
        XCTAssertEqual(WordList.korean("가 -5").count, 0)
        XCTAssertEqual(WordList(entries: [("x", Int.min), ("x", Int.max), ("y", Int.max)]).count, 2)
    }

    func testWordListReadsCRLFAndTabs() {
        // "\r\n" is one Character in Swift: splitting on "\n" alone read nothing from a Windows file.
        XCTAssertEqual(WordList.english("hello 5\r\nworld 3\r\n").count, 2)
        XCTAssertEqual(WordList.english("hello\t5\nworld  3\n").count, 2)
        XCTAssertEqual(WordList.korean("안녕 5\r\n").frequency(of: "dkssud"), 5)
    }

    func testBundledWordListsLoadWhole() throws {
        // A broken or truncated resource fails here instead of quietly turning English words Korean.
        let d = try LanguageDetector.bundled()
        XCTAssertGreaterThan(d.english.count, 40_000)
        XCTAssertGreaterThan(d.korean.count, 40_000)
    }

    func testEmptyAndOddInputToTheSmallFunctions() {
        XCTAssertEqual(detector.decide([], complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide([], complete: false, previous: .english), .english)
        XCTAssertEqual(KeyEncoder.keys(forHangul: ""), [])
        XCTAssertEqual(KeyEncoder.keys(forLatin: "", sentenceStart: true), [])
        for odd in ["안".decomposedStringWithCanonicalMapping, "\u{318D}", "\u{3164}", "e\u{301}", "😀"] {
            XCTAssertNil(KeyEncoder.keys(forHangul: odd), odd.debugDescription)
        }
        XCTAssertNil(KeyEncoder.keys(forLatin: "naïve", sentenceStart: false))
        for cap in ["", "e\u{301}", "ẞ", "ㄳ", "\u{0}", "\n", "🇰🇷"] {
            XCTAssertNil(Dubeolsik.letter(forKeycap: cap), cap.debugDescription)
        }
        XCTAssertEqual(Hangul.compose([]).text, "")
        XCTAssertEqual(TypingSession.render([], as: .english), "")
    }
}
