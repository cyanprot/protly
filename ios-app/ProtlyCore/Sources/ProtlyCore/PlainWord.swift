// The word being typed is plain text in the field, not marked text (typing-fixes 001). Each key turns the word
// Protly last wrote into the new one by deleting only the characters that changed and typing the new tail, as
// Apple's Korean keyboard does. Counts are Characters (grapheme clusters): one deleteBackward each.

public enum PlainWord {
    /// Delete the characters after the common prefix of `old` and `new`, then insert the rest of `new`.
    public static func edit(from old: String, to new: String) -> (deleting: Int, inserting: String) {
        let o = Array(old), n = Array(new)
        var i = 0
        while i < o.count, i < n.count, o[i] == n[i] { i += 1 }
        return (o.count - i, String(n[i...]))
    }

    /// What the keyboard sends for one `FieldEdit`, given the word it has written so far (`written`, "" when no
    /// word is being typed), and what `written` becomes. `.mark` and `.commit` change only the word; `.replace`
    /// (a flip of the committed word) deletes its own count and leaves `written` as it was.
    public static func step(_ edit: FieldEdit, written: String) -> Step {
        switch edit {
        case .mark(let text):
            let e = Self.edit(from: written, to: text)
            return Step(deleting: e.deleting, inserting: e.inserting, written: text)
        case .commit(let text):
            let e = Self.edit(from: written, to: text)
            return Step(deleting: e.deleting, inserting: e.inserting, written: "")
        case .replace(let count, let text):
            return Step(deleting: count, inserting: text, written: written)
        }
    }

    public struct Step: Sendable, Equatable {
        /// deleteBackward calls, one Character each, made first.
        public let deleting: Int
        /// One insertText after the deletes; "" sends nothing.
        public let inserting: String
        /// The word being typed after this step, as it is now in the field ("" once committed).
        public let written: String
    }
}
