/// Where Cancel puts the cursor (keyboard-ui 003, P6). A whole-field read moves the cursor to the end of the field in
/// steps. Each step is recorded when it is sent to the host and counted once the host shows it; a step the host never
/// shows is dropped. The keyboard waits for a step on its way to settle before it puts the cursor back, so only settled
/// steps are ever moved back over, and only while that text is still just before the cursor.
public struct CursorReturn: Sendable, Equatable {
    /// The text the reads moved the cursor over, in order: now just before the cursor.
    private var over = ""
    /// The before-context the host showed after the last counted step: where the reads left the cursor.
    private var at = ""
    /// A step sent to the host and not settled yet.
    private var inFlight = ""

    public init() {}

    /// A step is on its way: wait for it to settle before moving back.
    public var isMoving: Bool { !inFlight.isEmpty }

    /// A read starts at the cursor, whose before-context is `before`. A Retry from exactly where the last read left
    /// the cursor continues its record; anywhere else the old record no longer describes the cursor.
    public mutating func begin(before: String) {
        if over.isEmpty || before != at { clear() }
        inFlight = ""
    }

    /// The read is about to move the cursor over `chunk`.
    public mutating func sending(_ chunk: String) { inFlight = chunk }

    /// The host shows the step; `before` is the before-context it shows now.
    public mutating func applied(before: String) {
        over += inFlight
        at = before
        inFlight = ""
    }

    /// The host never showed the step (the read gave up waiting and never sends it again): it does not count.
    public mutating func notApplied() { inFlight = "" }

    /// Nothing to put back: a selection read, Read clipboard, the result replaced the text, or the call ended.
    public mutating func clear() {
        over = ""
        at = ""
        inFlight = ""
    }

    /// UTF-16 units to move back over the settled steps, 0 when nothing moved or the field changed since.
    public func back(before: String) -> Int {
        FieldGuard.canRestore(over, before: before) ? over.utf16.count : 0
    }
}
