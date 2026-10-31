import XCTest
@testable import ProtlyCore

/// keyboard-ui 003 (P6): Cancel puts the cursor back where it was before the field read moved it.
final class CursorReturnTests: XCTestCase {
    /// One read from a cursor whose before-context is `before`, over `chunks`, each shown by the host.
    private func read(_ c: inout CursorReturn, before: String, _ chunks: [String]) {
        c.begin(before: before)
        var now = before
        for chunk in chunks {
            c.sending(chunk)
            now += chunk
            c.applied(before: now)
        }
    }

    func testAFinishedReadGoesBackOverWhatItMovedOver() {
        var c = CursorReturn()
        read(&c, before: "hello", [" world", "\nagain"])
        XCTAssertEqual(c.back(before: "hello world\nagain"), " world\nagain".utf16.count)
        XCTAssertEqual(c.back(before: "hello world\nagain😀"), 0, "the field changed: stay")
    }

    /// A step on its way is not counted until it settles: the keyboard waits for it (isMoving) before moving back.
    func testAStepOnItsWayCountsOnlyOnceShown() {
        var c = CursorReturn()
        c.begin(before: "hello")
        c.sending(" world")
        XCTAssertTrue(c.isMoving)
        XCTAssertEqual(c.back(before: "hello"), 0)
        c.applied(before: "hello world")
        XCTAssertFalse(c.isMoving)
        XCTAssertEqual(c.back(before: "hello world"), 6)
    }

    /// A step the host never showed (the read gave up) is not counted: the cursor never went there.
    func testAStepTheHostNeverShowedDoesNotCount() {
        var c = CursorReturn()
        c.begin(before: "ok")
        c.sending("ok")
        c.notApplied()
        XCTAssertFalse(c.isMoving)
        XCTAssertEqual(c.back(before: "ok"), 0)
    }

    /// Retry after an error: the first read left the cursor at the end, the second moves nothing.
    func testARetryThatMovesNothingKeepsTheFirstOffset() {
        var c = CursorReturn()
        read(&c, before: "hello", [" world"])
        read(&c, before: "hello world", [])
        XCTAssertEqual(c.back(before: "hello world"), 6)
    }

    /// Retry from where a cut-short read stopped: the second read continues the record.
    func testARetryFromWhereTheFirstReadStoppedAddsToIt() {
        var c = CursorReturn()
        read(&c, before: "a", ["b"])
        read(&c, before: "ab", ["c"])
        XCTAssertEqual(c.back(before: "abc"), 2)
    }

    /// Retry after the user put the cursor back: the new read's offset replaces the first, never adds to it.
    func testARetryAfterTheCursorMovedReplacesTheFirstOffset() {
        var c = CursorReturn()
        read(&c, before: "hello", [" world"])
        read(&c, before: "hello wor", ["ld"])
        XCTAssertEqual(c.back(before: "hello world"), 2)
    }

    /// The cursor moved to another spot that also ends with the recorded text: a new record, not an added one.
    func testARetryElsewhereAfterTheSameTextStartsANewRecord() {
        var c = CursorReturn()
        read(&c, before: "one", ["\n"])
        read(&c, before: "one\ntwo\n", ["three"])
        XCTAssertEqual(c.back(before: "one\ntwo\nthree"), 5)
    }

    func testClearAndNoMove() {
        var c = CursorReturn()
        XCTAssertEqual(c.back(before: "x"), 0)
        read(&c, before: "", ["abc"])
        c.clear()
        XCTAssertEqual(c.back(before: "abc"), 0)
    }
}
