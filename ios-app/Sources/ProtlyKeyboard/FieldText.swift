import UIKit

/// Reads and replaces the whole field through the text document proxy.
/// The proxy only shows text around the cursor, so the cursor goes to the end first.
@MainActor
enum FieldText {
    /// One cursor step of a read, for Cancel (CursorReturn): sent to the host, then shown by it (with the
    /// before-context it shows now) or given up on.
    enum Move {
        case sending(String)
        case applied(before: String)
        case notApplied
    }

    /// The field text, or the selection when there is one. nil when the field is empty or the read was cancelled.
    /// `record` gets each cursor step as it is sent and then whether the host showed it. A cancel stops the read
    /// before its next step, never during one: a step on its way is always settled first, so Cancel moves back only
    /// over steps that landed (CursorReturn).
    static func read(_ proxy: UITextDocumentProxy, record: (Move) -> Void) async -> (text: String, isSelection: Bool)? {
        if let sel = proxy.selectedText, !sel.isEmpty { return (sel, true) }
        // The after-context often stops at a paragraph break, so one jump can land mid-text: repeat.
        for _ in 0..<10 {
            guard !Task.isCancelled else { return nil }  // cancelled before a move: never start one
            guard let after = proxy.documentContextAfterInput, !after.isEmpty else { break }
            let before = proxy.documentContextBeforeInput
            record(.sending(after))
            proxy.adjustTextPosition(byCharacterOffset: after.utf16.count)  // UTF-16 units
            // Hosts apply the move asynchronously: poll until the context changes (max 1 s). Either side counts: the
            // next chunk can read the same as this one (blank lines, a repeated line), the text before never does.
            // The wait ignores a cancel: the step settles first, then the loop stops before the next one.
            var moved = false
            for _ in 0..<50 {
                await pause()
                if proxy.documentContextAfterInput != after || proxy.documentContextBeforeInput != before {
                    moved = true
                    break
                }
            }
            guard moved else {
                record(.notApplied)
                break  // the host never reported the move: never issue it again
            }
            record(.applied(before: proxy.documentContextBeforeInput ?? ""))
        }
        guard !Task.isCancelled else { return nil }
        // A whitespace-only field counts as empty, as in the bar: the protly key reads the clipboard.
        guard let before = proxy.documentContextBeforeInput,
              !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (before, false)
    }

    /// 20 ms that a cancel does not cut short (Task.sleep would end at once).
    private static func pause() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { c.resume() }
        }
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
