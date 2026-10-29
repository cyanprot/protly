import XCTest
@testable import ProtlyCore

final class SuggestionSessionTests: XCTestCase {
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 50_000), ("there", 30_000)]),
        korean: WordList(entries: [("dkssud", 500), ("dkssudgktpdy", 300)]),  // 안녕 안녕하세요
        priorBonus: 2.0
    )

    private func type(_ s: String, into session: inout TypingSession) {
        for c in s { _ = session.type(KeyEvent(c)) }
    }

    func testSpaceNeverReplacesOnlyATapDoes() {
        var s = TypingSession(detector: detector, previous: .english)
        type("teh", into: &s)
        XCTAssertEqual(s.suggestion, "the")
        XCTAssertEqual(s.commit(), .commit("teh"))  // space, return, punctuation: what was typed
        XCTAssertNil(s.suggestion)
        type("teh", into: &s)
        XCTAssertEqual(s.accept(), .commit("the"))
    }

    func testAcceptTakesTheSuggestion() {
        var s = TypingSession(detector: detector, previous: .english)
        type("th", into: &s)
        XCTAssertEqual(s.suggestion, "the")
        XCTAssertEqual(s.accept(), .commit("the"))
        XCTAssertFalse(s.isComposing)
        XCTAssertNil(s.lastTail)
        XCTAssertNil(s.accept())
        XCTAssertEqual(s.suggester.learned.changes, 0)  // a pick teaches nothing
    }

    func testAcceptAKoreanCompletion() {
        var s = TypingSession(detector: detector, previous: .korean)
        type("dkssudg", into: &s)  // 안녕ㅎ
        XCTAssertEqual(s.suggestion, "안녕하세요")
        XCTAssertEqual(s.accept(), .commit("안녕하세요"))
        XCTAssertEqual(s.previous, .korean)
        XCTAssertEqual(s.keycapLanguage, .korean)
        XCTAssertEqual(s.suggester.learned.changes, 0)
    }

    func testAPickAfterAFlipTeachesTheFlip() {
        // "go" reads English after an English word; flipped to 해, the slot completes 해요.
        let d = LanguageDetector(
            english: WordList(entries: [("go", 900), ("good", 500)]),
            korean: WordList(entries: [("gody", 400)]),  // 해요
            priorBonus: 2.0
        )
        var s = TypingSession(detector: d, previous: .english)
        type("go", into: &s)
        XCTAssertEqual(s.flip(), .mark("해"))
        XCTAssertEqual(s.suggestion, "해요")
        XCTAssertEqual(s.accept(), .commit("해요"))
        XCTAssertEqual(s.suggester.learned.count(of: "gody", in: .korean), 1)
        XCTAssertEqual(s.suggester.learned.changes, 1)
    }

    func testFlippedWordGetsNoFixAndFlipsTeach() {
        var s = TypingSession(detector: detector, previous: .english)
        type("teh", into: &s)
        _ = s.flip()
        _ = s.flip()  // back to English, by hand
        XCTAssertNil(s.suggestion)  // the user chose this reading: no fix
        XCTAssertEqual(s.commit(), .commit("teh"))
        XCTAssertEqual(s.suggester.learned.changes, 0)  // flipped back to what was detected: nothing taught
        type("dkssud", into: &s)
        _ = s.commit()
        s.noteInserted(" ")
        XCTAssertEqual(s.flip(), .replace(deleting: 3, inserting: "dkssud "))
        XCTAssertEqual(s.suggester.learned.count(of: "dkssud", in: .english), 1)
    }

    func testFlippingAgainReplacesTheLearning() {
        // A committed word flipped there and back ends learned only in its final language.
        var s = TypingSession(detector: detector, previous: .english)
        type("dkssud", into: &s)
        _ = s.commit()  // 안녕, as detected
        s.noteInserted(" ")
        _ = s.flip()    // dkssud, taught as English
        XCTAssertEqual(s.flip(), .replace(deleting: 7, inserting: "안녕 "))
        XCTAssertEqual(s.suggester.learned.count(of: "dkssud", in: .english), 0)
        XCTAssertEqual(s.suggester.learned.count(of: "dkssud", in: .korean), 1)
        // Flipped while typing (taught at commit), then flipped back after the commit: the same rule.
        var t = TypingSession(detector: detector, previous: .korean)
        type("dkssud", into: &t)
        _ = t.flip()
        XCTAssertEqual(t.commit(), .commit("dkssud"))
        XCTAssertEqual(t.suggester.learned.count(of: "dkssud", in: .english), 1)
        _ = t.flip()
        XCTAssertEqual(t.suggester.learned.count(of: "dkssud", in: .english), 0)
        XCTAssertEqual(t.suggester.learned.count(of: "dkssud", in: .korean), 1)
    }

    func testAFlipTakesBackAnEarlierDaysLearning() {
        // "the" was taught as English by a flip on an earlier day; now it is flipped to Korean (솓).
        var s = TypingSession(detector: detector, previous: .english)
        s.suggester.learned.learn("the", as: .english)
        type("the", into: &s)
        XCTAssertEqual(s.commit(), .commit("the"))
        XCTAssertEqual(s.flip(), .replace(deleting: 3, inserting: "솓"))
        XCTAssertEqual(s.suggester.learned.count(of: "the", in: .english), 0)
        XCTAssertEqual(s.suggester.learned.count(of: "the", in: .korean), 1)
    }
}
