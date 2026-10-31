/// Where Cancel puts the cursor (keyboard-ui 003, P6). A whole-field read moves the cursor to the end of the field in
/// steps; each step is recorded as the text it moved over, even when the read is cancelled before it returns. Moving
/// back is safe only while that text is still just before the cursor.
public struct CursorReturn: Sendable, Equatable {
    /// The text the last read that moved moved over, now just before the cursor.
    private var over = ""
    /// What the read in progress has moved over so far.
    private var reading = ""

    public init() {}

    public mutating func begin() { reading = "" }

    /// The read is about to move the cursor over `chunk`.
    public mutating func moved(over chunk: String) { reading += chunk }

    /// The read finished or was cancelled. A read that moved replaces the earlier record, never adds to it (the user
    /// put the cursor back before a Retry). A read that moved nothing keeps it: a Retry re-reads a field the first
    /// read already moved to its end.
    public mutating func end() {
        if !reading.isEmpty { over = reading }
        reading = ""
    }

    /// Nothing to put back: a selection read, Read clipboard, or the result replaced the text.
    public mutating func clear() {
        over = ""
        reading = ""
    }

    /// UTF-16 units to move back, 0 when nothing moved or the field changed since.
    public func back(before: String) -> Int {
        FieldGuard.canRestore(over, before: before) ? over.utf16.count : 0
    }
}
