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
        // The field moved under the word: it was abandoned, nothing written.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi rk", written: "rk", committed: nil), "hi rk")
        // The context does not show the word: there is nothing to swap, so it is taken as it is.
        XCTAssertEqual(SpaceTrackpad.textBefore(context: "hi r", written: "rk", committed: "가"), "hi r")
    }

    /// R3: the trackpad starts sooner than KeyboardKit's 0.5 s hold, which other keys keep.
    func testSpaceLongPressDelay() {
        XCTAssertEqual(SpaceTrackpad.longPressDelay, 0.4)
    }
}
