// Whether the field still holds what protly read or inserted, so Insert and Undo delete only that text.
// The keyboard deletes one character per call, `count` times: a field edited since the read (a paste or a
// cut anywhere, the cursor moved) must stop the edit, not shift it onto the user's own text.

public enum FieldGuard {
    /// Insert over a whole-field read: the cursor is at the end and the text before it ends with all of it.
    public static func canReplace(_ original: String, before: String, after: String) -> Bool {
        after.isEmpty && !original.isEmpty && before.hasSuffix(original)
    }

    /// Undo: the text before the cursor still ends with all of the inserted text.
    public static func canUndo(_ inserted: String, before: String) -> Bool {
        !inserted.isEmpty && before.hasSuffix(inserted)
    }

    /// Cancel after a read: the cursor goes back only while the text the read moved over is still just before it.
    public static func canRestore(_ read: String, before: String) -> Bool {
        !read.isEmpty && before.hasSuffix(read)
    }
}
