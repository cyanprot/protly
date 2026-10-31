import Observation
import ProtlyCore

/// The streamed text of the open result card (keyboard-ui 003). Only ResultCard reads it, so a delta redraws the
/// card and nothing else: streamed text never goes through ProtlyMode, whose every write rebuilds the keys.
@MainActor
@Observable
final class ResultFeed {
    /// The translation so far, then the whole of it.
    var partial = ""
    /// The back translation, once the call is done.
    var back = ""
    /// The error that ended the call after text was on screen; the text stays.
    var failed: ActionError?

    func reset() {
        if !partial.isEmpty { partial = "" }
        if !back.isEmpty { back = "" }
        if failed != nil { failed = nil }
    }
}
