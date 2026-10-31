import XCTest
@testable import ProtlyCore

/// keyboard-ui 003, tower decision D-B: the keys wait during the field read, so the whole read ends within 2 s. A step
/// that started always gets its full settle wait, so Cancel's record (CursorReturn) never counts a step on its way.
final class FieldReadBudgetTests: XCTestCase {
    private let start: TimeInterval = 1_000

    func testANewStepStartsOnlyWhileItsFullWaitStillFits() {
        let b = FieldReadBudget(start: start)
        XCTAssertTrue(b.canStartStep(now: start))
        XCTAssertTrue(b.canStartStep(now: start + FieldReadBudget.total - FieldReadBudget.stepWait))
        XCTAssertFalse(b.canStartStep(now: start + FieldReadBudget.total - FieldReadBudget.stepWait + 0.001))
        XCTAssertFalse(b.canStartStep(now: start + FieldReadBudget.total))
    }

    func testAStepWaitsItsFullTimeWhateverTheTotal() {
        let b = FieldReadBudget(start: start)
        let sent = start + 0.9
        XCTAssertTrue(b.isWaiting(sentAt: sent, now: sent))
        XCTAssertTrue(b.isWaiting(sentAt: sent, now: sent + FieldReadBudget.stepWait - 0.001))
        XCTAssertFalse(b.isWaiting(sentAt: sent, now: sent + FieldReadBudget.stepWait))
    }

    func testTheLimits() {
        XCTAssertEqual(FieldReadBudget.total, 2)
        XCTAssertLessThanOrEqual(FieldReadBudget.stepWait, FieldReadBudget.total)
        XCTAssertEqual(FieldReadBudget.maxSteps, 10)
    }

    /// FieldText.read's loop against a host that shows each step after `latency` (nil: never), polled every `tick`.
    private func read(latency: TimeInterval?, needs: Int, tick: TimeInterval = 0.02)
        -> (applied: Int, dropped: Int, elapsed: TimeInterval) {
        let b = FieldReadBudget(start: start)
        var now = start, applied = 0, dropped = 0
        for _ in 0..<FieldReadBudget.maxSteps {
            guard b.canStartStep(now: now), applied < needs else { break }
            let sent = now
            var moved = false
            while b.isWaiting(sentAt: sent, now: now) {
                now += tick
                if let latency, now - sent >= latency {
                    moved = true
                    break
                }
            }
            guard moved else {
                dropped += 1
                break
            }
            applied += 1
        }
        return (applied, dropped, now - start)
    }

    func testTheWholeReadEndsWithinTheCapOnAnyHost() {
        for latency in [0.001, 0.02, 0.1, 0.3, 0.6, 0.99, 1.5, nil] as [TimeInterval?] {
            for needs in [1, 3, 10] {
                let r = read(latency: latency, needs: needs)
                XCTAssertLessThanOrEqual(r.elapsed, FieldReadBudget.total + 0.02 + 1e-9,
                                         "latency \(String(describing: latency)), \(needs) steps")
            }
        }
    }

    func testAFastHostIsReadWhole() {
        let r = read(latency: 0.02, needs: 10)
        XCTAssertEqual(r.applied, 10)
        XCTAssertEqual(r.dropped, 0)
    }

    /// A slow host hits the cap: the read stops before its next step, with every started step settled, and the
    /// keyboard shows the cut-short read's "Could not read the whole text".
    func testASlowHostIsCutShortBetweenSteps() {
        let r = read(latency: 0.3, needs: 10)
        XCTAssertEqual(r.applied, 4)  // started at 0, 0.3, 0.6 and 0.9 s; at 1.2 s a full wait no longer fits
        XCTAssertEqual(r.dropped, 0)
        XCTAssertLessThan(r.elapsed, FieldReadBudget.total)
    }

    /// A host that never shows the step: given up after the full step wait, as before the cap.
    func testAHostThatNeverMovesIsGivenUpOnAfterTheStepWait() {
        let r = read(latency: nil, needs: 3)
        XCTAssertEqual(r.applied, 0)
        XCTAssertEqual(r.dropped, 1)
        XCTAssertGreaterThanOrEqual(r.elapsed, FieldReadBudget.stepWait - 1e-9)
    }
}
