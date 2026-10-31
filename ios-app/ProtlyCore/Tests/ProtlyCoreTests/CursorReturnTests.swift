import XCTest
@testable import ProtlyCore

/// keyboard-ui 003 (P6): Cancel puts the cursor back where it was before the field read moved it.
final class CursorReturnTests: XCTestCase {
    /// One read over `chunks`, then its end.
    private func read(_ c: inout CursorReturn, _ chunks: [String]) {
        c.begin()
        for chunk in chunks { c.moved(over: chunk) }
        c.end()
    }

    func testAFinishedReadGoesBackOverWhatItMovedOver() {
        var c = CursorReturn()
        read(&c, [" world", "\nagain"])
        XCTAssertEqual(c.back(before: "hello world\nagain"), " world\nagain".utf16.count)
        XCTAssertEqual(c.back(before: "hello world\nagain😀"), 0, "the field changed: stay")
    }

    /// Cancel while the read still polls: the moves made so far count.
    func testACancelMidReadGoesBackOverTheMovesMadeSoFar() {
        var c = CursorReturn()
        c.begin()
        c.moved(over: " world")
        c.end()  // the cancel path ends the read early
        XCTAssertEqual(c.back(before: "hello world"), 6)
        // The cancelled read's own end later changes nothing.
        c.end()
        XCTAssertEqual(c.back(before: "hello world"), 6)
    }

    /// Retry after an error: the first read left the cursor at the end, the second moves nothing.
    func testARetryThatMovesNothingKeepsTheFirstOffset() {
        var c = CursorReturn()
        read(&c, [" world"])
        read(&c, [])
        XCTAssertEqual(c.back(before: "hello world"), 6)
    }

    /// Retry after the user put the cursor back: the new read's offset replaces the first, never adds to it.
    func testARetryThatMovesAgainReplacesTheFirstOffset() {
        var c = CursorReturn()
        read(&c, [" world"])
        read(&c, ["ld"])
        XCTAssertEqual(c.back(before: "hello world"), 2)
    }

    func testClearAndNoMove() {
        var c = CursorReturn()
        XCTAssertEqual(c.back(before: "x"), 0)
        read(&c, ["abc"])
        c.clear()
        XCTAssertEqual(c.back(before: "abc"), 0)
    }
}
