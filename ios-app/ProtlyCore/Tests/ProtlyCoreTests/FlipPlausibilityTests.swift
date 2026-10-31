import XCTest
@testable import ProtlyCore

// keyboard-ui 001 Task 1.2 (audit B4): the bar's left slot is drawn in the primary color only when the other
// reading is a word in that language's bundled list (en_50k, ko_50k); otherwise it is dimmed. Learned words do not
// count. A word still being typed counts when some listed word starts with it, or it would dim on every key.
final class FlipPlausibilityTests: XCTestCase {
    private static let bundled = try? LanguageDetector.bundled()

    /// The keys typed into a session with the bundled lists, read in `language` (flipped if the detector chose the
    /// other one), committed unless `composing`.
    private func session(_ typed: String, readAs language: Language, composing: Bool = false) throws -> TypingSession {
        let detector = try XCTUnwrap(Self.bundled)
        var s = TypingSession(detector: detector)
        for c in typed { _ = s.type(KeyEvent(c)) }
        if s.language != language { _ = s.flip() }
        XCTAssertEqual(s.language, language)
        if !composing { _ = s.commit() }
        return s
    }

    func testAKoreanReadingInTheListIsAWord() throws {
        let s = try session("dkssud", readAs: .english)
        XCTAssertEqual(s.alternative, "안녕")
        XCTAssertTrue(s.alternativeIsWord)
    }

    func testAKoreanReadingNotInTheListDims() throws {
        let s = try session("rkskek", readAs: .english)
        XCTAssertEqual(s.alternative, "가나다")
        XCTAssertFalse(s.alternativeIsWord)
    }

    func testAnEnglishReadingInTheListIsAWord() throws {
        let s = try session("hello", readAs: .korean)
        XCTAssertEqual(s.alternative, "hello")
        XCTAssertTrue(s.alternativeIsWord)
    }

    func testAMixedCaseEnglishReadingIsLookedUpLowercased() throws {
        let s = try session("Hello", readAs: .korean)
        XCTAssertEqual(s.alternative, "Hello")
        XCTAssertTrue(s.alternativeIsWord)
    }

    func testAHalfTypedWordIsNotDimmed() throws {
        let typing = try session("dkss", readAs: .english, composing: true)
        XCTAssertTrue(typing.isComposing)
        XCTAssertEqual(typing.alternative, "안ㄴ")
        XCTAssertTrue(typing.alternativeIsWord)  // 안녕 starts with these keys
        // The same keys as a finished word are not one.
        XCTAssertFalse(try session("dkss", readAs: .english).alternativeIsWord)
    }

    func testAHalfTypedEnglishReadingCountsByPrefix() throws {
        let s = try session("hel", readAs: .korean, composing: true)
        XCTAssertEqual(s.alternative, "hel")
        XCTAssertTrue(s.alternativeIsWord)
    }

    func testLearnedWordsDoNotCount() throws {
        var s = TypingSession(detector: try XCTUnwrap(Self.bundled))
        s.suggester.learned.learn("가나다", as: .korean)
        XCTAssertTrue(s.suggester.learned.count(of: "rkskek", in: .korean) > 0)
        for c in "rkskek" { _ = s.type(KeyEvent(c)) }
        if s.language != .english { _ = s.flip() }
        _ = s.commit()
        XCTAssertEqual(s.alternative, "가나다")
        XCTAssertFalse(s.alternativeIsWord)
    }

    func testNoDetectorYetNeverDims() {
        var s = TypingSession()
        for c in "rkskek" { _ = s.type(KeyEvent(c)) }
        XCTAssertNotNil(s.alternative)
        XCTAssertTrue(s.alternativeIsWord)
        _ = s.commit()
        XCTAssertNotNil(s.alternative)
        XCTAssertTrue(s.alternativeIsWord)
    }

    func testNoAlternativeIsNotAWord() throws {
        let fresh = TypingSession(detector: try XCTUnwrap(Self.bundled))
        XCTAssertNil(fresh.alternative)
        XCTAssertFalse(fresh.alternativeIsWord)
        XCTAssertNil(TypingSession().alternative)
        XCTAssertFalse(TypingSession().alternativeIsWord)
    }
}
