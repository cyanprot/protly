import XCTest
@testable import ProtlyCore

/// typing-fixes 003: the space bar trackpad (docs/research/2026-10-30-space-trackpad.md R4, section 5).
/// Slow moves here run at 50 pt/s (gain 1); offsets are UTF-16 units, as adjustTextPosition takes them.
final class SpaceTrackpadTests: XCTestCase {
    /// One move at 50 pt/s: below the speed where the gain starts.
    private func slow(_ pad: inout SpaceTrackpad, _ dx: Double) -> Int {
        pad.move(dx: dx, dt: abs(dx) / 50)
    }

    func testSlowDragMovesOneNarrowCharacterPerSixPoints() {
        var pad = SpaceTrackpad(before: "", after: "hello world")
        XCTAssertEqual(pad.move(dx: 30, dt: 0.6), 5)
        var short = SpaceTrackpad(before: "", after: "hello world")
        XCTAssertEqual(slow(&short, 35), 5)  // 5 pt short of the sixth character
    }

    func testWideGlyphCostsTwice() {
        var pad = SpaceTrackpad(before: "", after: "가나다라")
        XCTAssertEqual(pad.move(dx: 24, dt: 0.48), 2)
        var step = SpaceTrackpad(before: "", after: "가나다라")
        XCTAssertEqual(slow(&step, 6), 0)  // half a syllable moves nothing
        XCTAssertEqual(slow(&step, 6), 1)
    }

    func testRemainderCarriesAcrossEvents() {
        var pad = SpaceTrackpad(before: "", after: "hello")
        let offsets = (0..<10).map { _ in pad.move(dx: 1, dt: 0.1) }
        XCTAssertEqual(offsets, [0, 0, 0, 0, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(pad.move(dx: 1, dt: 0.1), 0)
        XCTAssertEqual(pad.move(dx: 1, dt: 0.1), 1)  // 12 pt in all: two characters
    }

    func testReverseWithinAStepDoesNotJitter() {
        var pad = SpaceTrackpad(before: "abc", after: "def")
        XCTAssertEqual(pad.move(dx: 4, dt: 0.1), 0)
        XCTAssertEqual(pad.move(dx: -4, dt: 0.1), 0)
        XCTAssertEqual(slow(&pad, -6), -1)  // back at zero: one full step left is one character
    }

    func testReversalCarriesTheRemainder() {
        var pad = SpaceTrackpad(before: "abc", after: "def")
        XCTAssertEqual([5, -2, 3].map { slow(&pad, Double($0)) }, [0, 0, 1])  // 5 - 2 + 3 = 6 pt
        var flick = SpaceTrackpad(before: String(repeating: "a", count: 20), after: String(repeating: "a", count: 20))
        XCTAssertEqual(flick.move(dx: 8, dt: 0.001), 4)  // 24 pt at 3x
        XCTAssertEqual(slow(&flick, -5), 0)  // the slow way back is not scaled by the flick
        XCTAssertEqual(slow(&flick, -1), -1)
    }

    func testGainDoesNotScaleTheCarriedRemainder() {
        var pad = SpaceTrackpad(before: "", after: String(repeating: "a", count: 200))
        XCTAssertEqual(slow(&pad, 5), 0)
        XCTAssertEqual(pad.move(dx: 60, dt: 0.05), 30)  // 5 + 180, not (5 + 60) x 3
        XCTAssertEqual(slow(&pad, 1), 1)
    }

    /// Callbacks that arrive bunched (a busy main thread) must not read as a flick.
    func testUnevenEventTimingDoesNotSpeedUpASlowDrag() {
        var pad = SpaceTrackpad(before: "", after: String(repeating: "a", count: 200))
        var total = 0
        for i in 0..<24 { total += pad.move(dx: 0.5, dt: i % 2 == 0 ? 0.001 : 0.0157) }  // about 60 pt/s
        XCTAssertEqual(total, 2)
    }

    func testFastFlickIsCappedAtMaxGain() {
        let text = String(repeating: "a", count: 200)
        var fast = SpaceTrackpad(before: "", after: text)
        XCTAssertEqual(fast.move(dx: 60, dt: 0.05), 30)  // 1200 pt/s: 3x
        var faster = SpaceTrackpad(before: "", after: text)
        XCTAssertEqual(faster.move(dx: 60, dt: 0.001), 30)
        var instant = SpaceTrackpad(before: "", after: text)
        XCTAssertEqual(instant.move(dx: 60, dt: 0), 30)  // no time between events: still 3x, not more
        var back = SpaceTrackpad(before: text, after: "")
        XCTAssertEqual(back.move(dx: -60, dt: 0.05), -30)
    }

    func testGainRisesLinearlyBetweenSlowAndFast() {
        var pad = SpaceTrackpad(before: "", after: String(repeating: "a", count: 100))
        // 300 pt/s: gain 1.8, 113.4 pt, 18 characters (10 at 1x, 31 at 3x).
        XCTAssertEqual(pad.move(dx: 63, dt: 0.21), 18)
    }

    func testStopsAtContextEnds() {
        var pad = SpaceTrackpad(before: "ab", after: "cd")
        XCTAssertEqual(slow(&pad, 100), 2)
        XCTAssertEqual(slow(&pad, 100), 0)
        XCTAssertEqual(slow(&pad, -6), -1)  // the push past the end is dropped: the way back starts at once
        XCTAssertEqual(slow(&pad, -1000), -3)
        XCTAssertEqual(slow(&pad, -100), 0)
        XCTAssertEqual(slow(&pad, 6), 1)
        var empty = SpaceTrackpad(before: "", after: "")
        XCTAssertEqual(slow(&empty, 100), 0)
        XCTAssertEqual(slow(&empty, -100), 0)
    }

    func testRemainderCarriesAcrossWidthChange() {
        var pad = SpaceTrackpad(before: "", after: "a가a")
        XCTAssertEqual([10, 7, 1].map { slow(&pad, Double($0)) }, [1, 0, 1])  // 4 + 7 < 12, 4 + 8 = 12
    }

    func testMultiScalarGraphemesMoveAsOne() {
        var accent = SpaceTrackpad(before: "xe\u{0301}", after: "")
        XCTAssertEqual(slow(&accent, -6), -2)
        var crlf = SpaceTrackpad(before: "x\r\n", after: "")
        XCTAssertEqual(slow(&crlf, -6), -2)
        var jamo = SpaceTrackpad(before: "\u{1100}\u{1161}", after: "")  // conjoining jamo: one wide syllable
        XCTAssertEqual(slow(&jamo, -12), -2)
    }

    func testNonFiniteInputs() {
        var pad = SpaceTrackpad(before: "", after: String(repeating: "a", count: 20))
        XCTAssertEqual(pad.move(dx: .nan, dt: 0.1), 0)
        XCTAssertEqual(pad.move(dx: .infinity, dt: 0.1), 0)
        XCTAssertEqual(slow(&pad, 6), 1)  // the remainder was not poisoned
        XCTAssertEqual(pad.move(dx: 6, dt: .infinity), 1)  // no usable time: slow
        XCTAssertEqual(pad.move(dx: 6, dt: .nan), 1)
        XCTAssertEqual(pad.move(dx: 6, dt: -1), 3)  // time went backwards: the shortest interval, 3x
    }

    func testWholeGraphemesInUTF16() {
        let text = "❤️👨‍👩‍👧🇰🇷가a"
        var right = SpaceTrackpad(before: "", after: text)
        XCTAssertEqual([12, 12, 12, 12, 6].map { slow(&right, Double($0)) }, [2, 8, 4, 1, 1])
        XCTAssertEqual(slow(&right, 100), 0)
        var left = SpaceTrackpad(before: text, after: "")
        XCTAssertEqual([-6, -12, -12, -12, -12].map { slow(&left, Double($0)) }, [-1, -1, -4, -8, -2])
        XCTAssertEqual(slow(&left, -100), 0)
    }

    func testCostOfEachKindOfGrapheme() {
        for narrow: Character in ["a", "Z", "1", " ", ".", "é", "\n", "ñ", "ß"] {
            XCTAssertEqual(SpaceTrackpad.cost(of: narrow), SpaceTrackpad.pointsPerNarrow, "\(narrow)")
        }
        for wide: Character in ["가", "힣", "ㄱ", "ㅏ", "漢", "か", "カ", "Ａ", "😀", "❤️", "🇰🇷", "👍🏽", "1️⃣"] {
            XCTAssertEqual(SpaceTrackpad.cost(of: wide), SpaceTrackpad.pointsPerWide, "\(wide)")
        }
        XCTAssertEqual(SpaceTrackpad.pointsPerWide, 2 * SpaceTrackpad.pointsPerNarrow)
    }

    func testFirstTrackedEventOnlySetsTheStart() {
        var pad = SpaceTrackpad(before: "", after: "hello world")
        XCTAssertEqual(pad.track(x: 100, y: 40, time: 5), 0)
        XCTAssertEqual(pad.track(x: 112, y: 40, time: 5.24), 2)  // 12 pt at 50 pt/s
    }

    /// R1: KeyboardKit dropped every step while the finger was 50 pt above or below the start (the "stall").
    /// SpaceTrackpad ignores y by design; this guards against a later change starting to use it. The keyboard side
    /// (KeyboardKit's threshold lifted) is a source rule, and phone check P3 is the real proof.
    func testVerticalDriftKeepsHorizontal() {
        let text = String(repeating: "word ", count: 20)
        var level = SpaceTrackpad(before: text, after: "")
        var drifting = level
        var a = level.track(x: 200, y: 0, time: 0)
        var b = drifting.track(x: 200, y: 0, time: 0)
        for i in 1...10 {
            let x = 200 - Double(i) * 10, t = Double(i) * 0.2  // left 100 pt at 50 pt/s
            a += level.track(x: x, y: 0, time: t)
            b += drifting.track(x: x, y: -6 * Double(i), time: t)  // the thumb rises 60 pt on the way
        }
        XCTAssertEqual(a, -16)
        XCTAssertEqual(b, a)
        var down = SpaceTrackpad(before: text, after: "")
        XCTAssertEqual(down.track(x: 200, y: 0, time: 0), 0)
        XCTAssertEqual(down.track(x: 100, y: 300, time: 2), -16)  // even far below the keyboard
    }

    // MARK: The snapshot at drag start (Sprint 001: the word being typed is plain text, not marked)

    /// Replaces the research's testMarkedWordIsInTheSnapshot: the word is plain text at the end of `before`.
    func testWordBeingTypedIsInTheSnapshot() {
        let before = SpaceTrackpad.textBefore(context: "오늘 진짜", written: "진짜", committed: "진짜")
        XCTAssertEqual(before, "오늘 진짜")
        var pad = SpaceTrackpad(before: before, after: "")
        XCTAssertEqual(slow(&pad, 6), 0)  // the caret is after the word: nothing to its right
        XCTAssertEqual(slow(&pad, -12), -1)  // 오늘 진|짜
    }

    /// Phone check P5: 안녕 with no space, hold space, one step left: 안|녕, nothing lost.
    func testOneStepLeftFromAWordWithNoSpace() {
        var pad = SpaceTrackpad(
            before: SpaceTrackpad.textBefore(context: "안녕", written: "안녕", committed: "안녕"), after: "")
        XCTAssertEqual(slow(&pad, -12), -1)
        XCTAssertEqual(slow(&pad, -12), -1)
        XCTAssertEqual(slow(&pad, -12), 0)
    }

    func testCommitThatChangesTheWordIsInTheSnapshot() {
        // The proxy was read before the commit; a read after it may not show the commit yet.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi rk", written: "rk", committed: "가"), "hi 가")
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "rk", written: "rk", committed: "가"), "가")
    }

    func testNoCommitLeavesTheContext() {
        // No word being typed.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi ", written: "", committed: nil), "hi ")
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi ", written: "", committed: "x"), "hi ")
        // The field moved under the word: it was abandoned, nothing written.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi rk", written: "rk", committed: nil), "hi rk")
        // The context does not show the word: there is nothing to swap, so it is taken as it is.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi r", written: "rk", committed: "가"), "hi r")
    }
}
