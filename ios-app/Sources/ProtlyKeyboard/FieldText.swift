import UIKit

/// Reads and replaces the whole field through the text document proxy.
/// The proxy only shows text around the cursor, so the cursor goes to the end first.
@MainActor
enum FieldText {
    /// The field text, or the selection when there is one. nil when the field is empty or the read was cancelled.
    /// `onMove` gets the text each cursor move goes over, before the move: Cancel can put the cursor back even when
    /// the read never returns its text (CursorReturn).
    static func read(_ proxy: UITextDocumentProxy, onMove: (String) -> Void) async -> (text: String, isSelection: Bool)? {
        if let sel = proxy.selectedText, !sel.isEmpty { return (sel, true) }
        // The after-context often stops at a paragraph break, so one jump can land mid-text: repeat.
        for _ in 0..<10 {
            guard let after = proxy.documentContextAfterInput, !after.isEmpty else { break }
            onMove(after)
            proxy.adjustTextPosition(byCharacterOffset: after.utf16.count)  // UTF-16 units
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
        return (before, false)
    }

    /// Cancel after a read (P6): the cursor goes back where it was before `read` moved it. The caller checks first
    /// that the text moved over is still just before the cursor (CursorReturn.back).
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
