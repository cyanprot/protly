import KeyboardKit
import ProtlyCore

/// Letters and backspace inside a word go to ProtlyCore's TypingSession; everything else to KeyboardKit,
/// whose text calls the controller intercepts to commit the word first.
final class ProtlyActionHandler: KeyboardAction.StandardActionHandler {
    weak var host: KeyboardViewController?

    override func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction, replaced: Bool) {
        // KeyboardKit calls this from button gestures, always on the main thread.
        MainActor.assumeIsolated {
            if !handleInWord(gesture, on: action) {
                super.handle(gesture, on: action, replaced: replaced)
            }
            guard let host else { return }
            if case .shift = action {
                host.mode.manualShift = keyboardContext.keyboardCase.isUppercasedOrCapslocked
            } else if gesture == .release || (gesture == .press && action == .backspace) {
                // Shift then space/backspace/123: the manual shift is spent, or the next auto-capital
                // sentence start would show ㅃㅉㄸ.
                host.mode.manualShift = false
            }
        }
    }

    /// true when protly handled the gesture itself.
    @MainActor
    private func handleInWord(_ gesture: Keyboard.Gesture, on action: KeyboardAction) -> Bool {
        guard let host else { return false }
        switch (gesture, action) {
        // The invisible edge keys beside ㅁ/ㅣ and ㅋ/ㅡ (iPhoneLayoutService adds them) type the same letter.
        case (.release, .character(let cap)), (.release, .characterMargin(let cap)):
            guard let letter = Dubeolsik.letter(forKeycap: cap) else { return false }
            host.typeLetter(letter)
            return true
        case (.press, .backspace), (.repeatPress, .backspace):
            guard host.backspaceInWord() else { return false }
            tryTriggerFeedback(for: gesture, on: action)
            return true
        default:
            return false
        }
    }
}
