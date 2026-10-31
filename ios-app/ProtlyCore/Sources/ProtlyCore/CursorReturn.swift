/// Where Cancel puts the cursor (keyboard-ui 003, P6). A whole-field read moves the cursor to the end of the field in
/// steps. Each step is recorded when it is sent to the host and counted once the host shows it, so Cancel works mid-read
/// too, even while a move is still on its way. Moving back is safe only while that text is still just before the cursor.
public struct CursorReturn: Sendable, Equatable {
    /// The text the reads moved the cursor over, in order: now just before the cursor.
    private var over = ""
    /// A move sent to the host and not seen there yet.
    private var inFlight = ""

    public init() {}

    /// A read starts at the cursor, whose before-context is `before`. A Retry that starts where the last read left
    /// the cursor continues its record; once the cursor moved since, the old record no longer describes it.
    public mutating func begin(before: String) {
        if !FieldGuard.canRestore(over, before: before) { over = "" }
        inFlight = ""
    }

    /// The read is about to move the cursor over `chunk`.
    public mutating func sending(_ chunk: String) { inFlight = chunk }

    /// The host shows the move: it counts.
    public mutating func applied() {
        over += inFlight
        inFlight = ""
    }

    /// The host never showed the move (the read gave up waiting and never sends it again): it does not count.
    public mutating func notApplied() { inFlight = "" }

    /// Nothing to put back: a selection read, Read clipboard, the result replaced the text, or the call ended.
    public mutating func clear() {
        over = ""
        inFlight = ""
    }

    /// UTF-16 units to move back, 0 when nothing moved or the field changed since. A move still in flight counts
    /// whether or not the before-context shows it yet: the host applies moves in the order they were sent, so a move
    /// back sent now lands after it.
    public func back(before: String) -> Int {
        let all = over + inFlight
        if FieldGuard.canRestore(all, before: before) { return all.utf16.count }
        guard !inFlight.isEmpty, over.isEmpty || FieldGuard.canRestore(over, before: before) else { return 0 }
        return all.utf16.count
    }
}
