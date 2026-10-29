import XCTest
@testable import ProtlyCore

final class TypingSessionTests: XCTestCase {
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 1000), ("hi", 800), ("go", 500)]),
        korean: WordList(entries: [("go", 500), ("dkssud", 50)]),  // 해, 안녕
        priorBonus: 2.0
    )

    private func type(_ s: String, into session: inout TypingSession) -> [FieldEdit] {
        s.map { session.type(KeyEvent($0)) }
    }

    func testKoreanWordIsMarkedThenCommitted() {
        var s = TypingSession(detector: detector)
        let edits = type("dkssud", into: &s)
        XCTAssertEqual(edits.last, .mark("안녕"))
        XCTAssertEqual(s.commit(), .commit("안녕"))
        XCTAssertFalse(s.isComposing)
        XCTAssertEqual(s.previous, .korean)
    }

    func testEnglishWordShowsLatinWhileTyping() {
        var s = TypingSession(detector: detector, previous: .korean)
        _ = type("hel", into: &s)        // ㅗ first: not Hangul
        XCTAssertEqual(s.language, .english)
        XCTAssertEqual(type("lo", into: &s).last, .mark("hello"))
        XCTAssertEqual(s.commit(), .commit("hello"))
        XCTAssertEqual(s.keycapLanguage, .english)
    }

    func testBackspaceDropsOneKeyAndRecomposes() {
        var s = TypingSession(detector: detector)
        _ = type("rkr", into: &s)        // 각
        XCTAssertEqual(s.backspace(), .mark("가"))
        XCTAssertEqual(s.backspace(), .mark("ㄱ"))
        XCTAssertEqual(s.backspace(), .mark(""))
        XCTAssertNil(s.backspace())      // nothing composing: the keyboard deletes
    }

    func testFlipWhileTypingSticksUntilCommit() {
        var s = TypingSession(detector: detector)
        _ = type("dkssud", into: &s)
        XCTAssertEqual(s.alternative, "dkssud")
        XCTAssertEqual(s.flip(), .mark("dkssud"))
        XCTAssertEqual(s.type(KeyEvent("s")), .mark("dkssuds"))  // forced English holds
        XCTAssertEqual(s.commit(), .commit("dkssuds"))
        XCTAssertEqual(s.previous, .english)
    }

    func testFlipCommittedWordReachesOverTheSpace() {
        var s = TypingSession(detector: detector)
        _ = type("dkssud", into: &s)
        _ = s.commit()
        s.noteInserted(" ")
        XCTAssertEqual(s.lastTail, "안녕 ")
        XCTAssertEqual(s.alternative, "dkssud")
        XCTAssertEqual(s.flip(), .replace(deleting: 3, inserting: "dkssud "))
        XCTAssertEqual(s.previous, .english)
        XCTAssertEqual(s.flip(), .replace(deleting: 7, inserting: "안녕 "))  // and back
    }

    func testTypingOrForgettingEndsTheFlip() {
        var s = TypingSession(detector: detector)
        _ = type("dkssud", into: &s)
        _ = s.commit()
        s.forgetLast()
        XCTAssertNil(s.lastTail)
        XCTAssertNil(s.flip())
    }

    func testWithoutDetectorHangulRuleDecides() {
        var s = TypingSession(detector: nil)
        XCTAssertEqual(type("dkssud", into: &s).last, .mark("안녕"))
        _ = s.commit()
        XCTAssertEqual(type("hello", into: &s).last, .mark("hello"))
        _ = s.commit()
        // After an English word, valid Hangul shows as English while typing but commits as Korean.
        XCTAssertEqual(type("dkssud", into: &s).last, .mark("dkssud"))
        XCTAssertEqual(s.commit(), .commit("안녕"))
    }

    func testAbandonKeepsTheAbandonedWordsLanguage() {
        var s = TypingSession(detector: detector, previous: .english)
        _ = type("dkssud", into: &s)
        s.abandon()
        XCTAssertFalse(s.isComposing)
        XCTAssertNil(s.alternative)
        XCTAssertEqual(s.previous, .korean)  // the word stays in the field (or was sent) as Korean
        XCTAssertEqual(s.keycapLanguage, .korean)
    }

    func testAbandonAfterFlipClearsTheForcedLanguage() {
        var s = TypingSession(detector: detector, previous: .korean)
        _ = type("dkssud", into: &s)
        _ = s.flip()  // forced English
        s.abandon()
        XCTAssertEqual(s.previous, .english)
        XCTAssertEqual(type("dkssud", into: &s).last, .mark("안녕"))  // decided again, not forced
    }

    func testTypingAfterCommitEndsTheFlip() {
        var s = TypingSession(detector: detector)
        _ = type("dkssud", into: &s)
        _ = s.commit()
        s.noteInserted(" ")
        _ = type("the", into: &s)
        XCTAssertNil(s.lastTail)
        XCTAssertEqual(s.alternative, "솓")  // the new word's other reading, not 안녕's
        XCTAssertEqual(s.flip(), .mark("솓"))
    }

    func testManualShiftReachesKoreanAndAutomaticDoesNot() {
        var s = TypingSession(detector: detector)
        XCTAssertEqual(s.type(KeyEvent("q", .automatic)), .mark("ㅂ"))
        _ = s.backspace()
        XCTAssertEqual(s.type(KeyEvent("q", .manual)), .mark("ㅃ"))
    }
}
