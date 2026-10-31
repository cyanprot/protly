import UIKit

/// Reads and replaces the whole field through the text document proxy.
/// The proxy only shows text around the cursor, so the cursor goes to the end first.
@MainActor
enum FieldText {
    /// The field text, or the selection when there is one. nil when the field is empty. `moved`: how far the read
    /// moved the cursor, in UTF-16 units, for `restore`.
    static func read(_ proxy: UITextDocumentProxy) async -> (text: String, isSelection: Bool, moved: Int)? {
        if let sel = proxy.selectedText, !sel.isEmpty { return (sel, true, 0) }
        var offset = 0
        // The after-context often stops at a paragraph break, so one jump can land mid-text: repeat.
        for _ in 0..<10 {
            guard let after = proxy.documentContextAfterInput, !after.isEmpty else { break }
            proxy.adjustTextPosition(byCharacterOffset: after.utf16.count)  // UTF-16 units
            offset += after.utf16.count
            // Hosts apply the move asynchronously: poll until the after-context changes (max 1 s).
            var moved = false
            for _ in 0..<50 {
                do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return nil }  // cancelled: stop touching the field
                if proxy.documentContextAfterInput != after { moved = true; break }
            }
            guard moved else { break }  // the host never reported the move: never issue it again
        }
        // A whitespace-only field counts as empty, as in the bar: the protly key reads the clipboard.
        guard let before = proxy.documentContextBeforeInput,
              !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (before, false, offset)
    }

    /// Cancel after a read (P6): the cursor goes back where it was before `read` moved it. The caller checks first
    /// that the field still holds what was read (FieldGuard.canRestore).
    static func restore(_ moved: Int, _ proxy: UITextDocumentProxy) {
        guard moved > 0 else { return }
        proxy.adjustTextPosition(byCharacterOffset: -moved)
    }

    /// Replace what `read` returned (cursor at the end, or the selection) with new text.
    static func replace(_ old: String, isSelection: Bool, with new: String, _ proxy: UITextDocumentProxy) {
        if isSelection {
            proxy.insertText(new)  // typing over a selection replaces it
            return
        }
        for _ in old { proxy.deleteBackward() }  // one grapheme per call
        proxy.insertText(new)
    }
}
