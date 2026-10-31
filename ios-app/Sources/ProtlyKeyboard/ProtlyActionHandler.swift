import KeyboardKit
import ProtlyCore
import UIKit

/// Letters and backspace inside a word go to ProtlyCore's TypingSession; everything else to KeyboardKit,
/// whose text calls the controller intercepts to commit the word first.
final class ProtlyActionHandler: KeyboardAction.StandardActionHandler {
    weak var host: KeyboardViewController?
    /// The space bar trackpad of the drag in progress (typing-fixes 003).
    private var drag = SpaceDrag()

    override func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction, replaced: Bool) {
        // KeyboardKit calls this from button gestures, always on the main thread.
        MainActor.assumeIsolated {
            // The field read is walking the cursor through the text (a few steps, usually well under a second): a key
            // now would land mid-text and join the text sent, so the keys wait.
            if host?.isReadingField == true { return }
            if action == .space, gesture == .press || gesture == .release || gesture == .end {
                drag.reset()  // a new press or the end of a drag: the next trackpad takes a new snapshot
            }
            if case .shift = action, gesture == .release, let host, host.mode.korean, !host.mode.manualShift,
               keyboardContext.keyboardCase == .uppercased {
                // Auto-capital is invisible on Korean keycaps, so this tap means "shift on" (ㅃㅉㄸ), not off.
                // KeyboardKit's release toggle then goes .lowercased -> .uppercased.
                keyboardContext.keyboardCase = .lowercased
            }
            if !handleInWord(gesture, on: action) {
                super.handle(gesture, on: action, replaced: replaced)
            }
            guard let host else { return }
            var manual = host.mode.manualShift
            if case .shift = action {
                // Shift acts on release; reading it on press would flag an auto-capital as manual.
                if gesture == .release { manual = keyboardContext.keyboardCase.isUppercasedOrCapslocked }
            } else if gesture == .release || (gesture == .press && action == .backspace) {
                // Shift then space/backspace/123: the manual shift is spent, or the next auto-capital
                // sentence start would show ㅃㅉㄸ.
                manual = false
            }
            // @Published fires on every write; an unchanged write would rebuild the keyboard on each key.
            if host.mode.manualShift != manual { host.mode.manualShift = manual }
        }
    }

    /// Once space is held (typing-fixes 003), Protly's SpaceTrackpad moves the cursor instead of KeyboardKit's drag
    /// math, through the controller's adjustTextPosition, which forgets the field model. Other drags keep
    /// KeyboardKit's behaviour.
    override func handleDrag(on action: KeyboardAction, from startLocation: CGPoint, to currentLocation: CGPoint) {
        guard action == .space else {
            super.handleDrag(on: action, from: startLocation, to: currentLocation)
            return
        }
        // KeyboardKit calls this from button gestures, always on the main thread.
        MainActor.assumeIsolated {
            if host?.isReadingField == true { return }  // as in handle: the field read owns the cursor
            guard let host else {
                super.handleDrag(on: action, from: startLocation, to: currentLocation)
                return
            }
            guard keyboardContext.settings.spaceLongPressBehavior.shouldMoveInputCursor,
                  keyboardContext.isSpaceDragGestureActive else {
                drag.reset()  // still holding, or the drag ended: no trackpad yet
                return
            }
            // Read before the commit below, so its work is not counted as drag time (the next move would read fast).
            let now = ProcessInfo.processInfo.systemUptime
            // The first event of a touch commits the word and takes the snapshot; it only sets the start, as in
            // KeyboardKit. A new start location is a new touch, even if a cancelled one sent no release.
            let offset = drag.move(startX: Double(startLocation.x), startY: Double(startLocation.y),
                                   x: Double(currentLocation.x), y: Double(currentLocation.y), time: now,
                                   snapshot: { host.beginSpaceDrag() })
            if offset != 0 { host.adjustTextPosition(by: offset) }
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
