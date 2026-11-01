import Observation
import ProtlyCore

/// The streamed text of one call's result card (keyboard-ui 003), a new one per call, so a card fading out keeps its
/// own. Only ResultCard reads it, so a delta redraws the card and nothing else: streamed text never goes through
/// ProtlyMode, whose every write rebuilds the keys.
@MainActor
@Observable
final class ResultFeed {
    /// The translation so far, then the whole of it.
    var partial = ""
    /// The back translation, once the call is done.
    var back = ""
    /// The error that ended the call after text was on screen; the text stays.
    var failed: ActionError?
}
