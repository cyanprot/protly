import XCTest
@testable import ProtlyCore

/// typing-fixes 003: one space drag at a time. The keyboard drops the trackpad on a space press, release or end, but
/// a touch the system cancels mid-drag (a notification, Control Center, a system gesture) may send none of them: the
/// next drag's new start location must still drop it.
final class SpaceDragTests: XCTestCase {
    /// Hands out the given snapshots in order and counts the calls.
    private final class Snapshots {
        private var pads: [SpaceTrackpad]
        private(set) var taken = 0
        init(_ pads: [SpaceTrackpad]) { self.pads = pads }
        func next() -> SpaceTrackpad {
            taken += 1
            return pads.isEmpty ? SpaceTrackpad(before: "", after: "") : pads.removeFirst()
        }
    }

    func testSnapshotTakenOncePerDrag() {
        let snapshots = Snapshots([SpaceTrackpad(before: "", after: "hello world")])
        var drag = SpaceDrag()
        var total = 0
        for i in 0..<5 {  // right 48 pt at 50 pt/s
            total += drag.move(startX: 100, startY: 20, x: 100 + Double(i) * 12, y: 20, time: Double(i) * 0.24,
                               snapshot: snapshots.next)
        }
        XCTAssertEqual(snapshots.taken, 1)
        XCTAssertEqual(total, 8)
    }

    func testNewStartLocationResetsTheTrackpad() {
        let snapshots = Snapshots([
            SpaceTrackpad(before: "", after: "hello world"),  // the first drag: the caret at the start
            SpaceTrackpad(before: "hello world", after: ""),  // the field after the cancelled drag
        ])
        var drag = SpaceDrag()
        XCTAssertEqual(drag.move(startX: 100, startY: 20, x: 100, y: 20, time: 0, snapshot: snapshots.next), 0)
        XCTAssertEqual(drag.move(startX: 100, startY: 20, x: 115, y: 20, time: 0.3, snapshot: snapshots.next), 2)
        // The system cancelled that touch: no release or end, no reset. A new touch starts elsewhere.
        XCTAssertEqual(drag.move(startX: 300, startY: 22, x: 300, y: 22, time: 5, snapshot: snapshots.next), 0,
                       "the first event of the new drag only sets its start, not a move from the old finger")
        XCTAssertEqual(snapshots.taken, 2, "the new drag takes its own snapshot")
        // Left 30 pt: five characters back from the end of the new snapshot. The old trackpad (caret after "he") has
        // only two to its left.
        XCTAssertEqual(drag.move(startX: 300, startY: 22, x: 270, y: 22, time: 5.6, snapshot: snapshots.next), -5)
    }

    func testSameStartKeepsTheCarry() {
        let snapshots = Snapshots([SpaceTrackpad(before: "", after: "hello world")])
        var drag = SpaceDrag()
        _ = drag.move(startX: 50, startY: 0, x: 50, y: 0, time: 0, snapshot: snapshots.next)
        XCTAssertEqual(drag.move(startX: 50, startY: 0, x: 54, y: 0, time: 0.08, snapshot: snapshots.next), 0)
        XCTAssertEqual(drag.move(startX: 50, startY: 0, x: 56, y: 0, time: 0.12, snapshot: snapshots.next), 1)
        XCTAssertEqual(snapshots.taken, 1)
    }

    func testResetDropsTheTrackpad() {
        let snapshots = Snapshots([
            SpaceTrackpad(before: "", after: "hello world"), SpaceTrackpad(before: "", after: "hello world"),
        ])
        var drag = SpaceDrag()
        _ = drag.move(startX: 50, startY: 0, x: 50, y: 0, time: 0, snapshot: snapshots.next)
        XCTAssertEqual(drag.move(startX: 50, startY: 0, x: 54, y: 0, time: 0.08, snapshot: snapshots.next), 0)
        drag.reset()  // a release: the same start location again must still take a new snapshot
        XCTAssertFalse(drag.isActive)
        XCTAssertEqual(drag.move(startX: 50, startY: 0, x: 50, y: 0, time: 3, snapshot: snapshots.next), 0)
        XCTAssertEqual(snapshots.taken, 2)
        XCTAssertTrue(drag.isActive)
        // The 4 pt carried in the dropped trackpad is gone: 2 pt more is not a step.
        XCTAssertEqual(drag.move(startX: 50, startY: 0, x: 52, y: 0, time: 3.04, snapshot: snapshots.next), 0)
    }
}
