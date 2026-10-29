import UIKit

/// Reads and replaces the whole field through the text document proxy.
/// The proxy only shows text around the cursor, so the cursor goes to the end first.
@MainActor
enum FieldText {
    /// The field text, or the selection when there is one. nil when the field is empty.
    static func read(_ proxy: UITextDocumentProxy) async -> (text: String, isSelection: Bool)? {
        if let sel = proxy.selectedText, !sel.isEmpty { return (sel, true) }
        // The after-context often stops at a paragraph break, so one jump can land mid-text: repeat.
        for _ in 0..<10 {
            guard let after = proxy.documentContextAfterInput, !after.isEmpty else { break }
            proxy.adjustTextPosition(byCharacterOffset: after.utf16.count)  // UTF-16 units
            // Hosts apply the move asynchronously: poll until the after-context changes (max 1 s).
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 20_000_000)
                if proxy.documentContextAfterInput != after { break }
            }
        }
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { return nil }
        return (before, false)
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
