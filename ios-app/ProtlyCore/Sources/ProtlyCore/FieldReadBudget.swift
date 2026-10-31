import Foundation

/// The time limits of one whole-field read (keyboard-ui 003, tower decision D-B). The keys wait while the read walks
/// the cursor to the end of the field (a key then would land mid-text), so the whole read ends within `total`.
/// A step that started always gets its full `stepWait` to settle: the cap only stops the read before its next step,
/// so Cancel's record (CursorReturn) never has to guess about a step on its way. A read stopped by the cap leaves
/// text after the cursor and ends as any cut-short read does ("Could not read the whole text").
public struct FieldReadBudget: Sendable, Equatable {
    /// The longest the keys wait for one read, in seconds.
    public static let total: TimeInterval = 2
    /// How long one step waits for the host to show the move before giving up on it.
    public static let stepWait: TimeInterval = 1
    /// The after-context often stops at a paragraph break, so the read repeats, at most this many times.
    public static let maxSteps = 10

    /// systemUptime when the read started.
    public let start: TimeInterval

    public init(start: TimeInterval) {
        self.start = start
    }

    /// A new step may start: its full settle wait still ends within `total`.
    public func canStartStep(now: TimeInterval) -> Bool {
        now - start + Self.stepWait <= Self.total
    }

    /// The step sent at `sentAt` is still waited for.
    public func isWaiting(sentAt: TimeInterval, now: TimeInterval) -> Bool {
        now - sentAt < Self.stepWait
    }
}
