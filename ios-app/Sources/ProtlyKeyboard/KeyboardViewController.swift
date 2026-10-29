import KeyboardKit
import ProtlyCore
import SwiftUI
import UIKit

/// State the SwiftUI tree observes besides KeyboardKit's own context.
@MainActor
final class ProtlyMode: ObservableObject {
    @Published var korean = true
    /// Shift is on because the user pressed it (not auto-capitalization).
    @Published var manualShift = false
    @Published var alternative: String?
}

@objc(KeyboardViewController)
final class KeyboardViewController: KeyboardInputViewController {
    let mode = ProtlyMode()
    private(set) var session = TypingSession()
    /// Marked text currently in the field, mirrored here because the proxy's context excludes it.
    private var marked = ""
    /// The text before the word being typed, taken at its first key. The proxy's context excludes the mark,
    /// so it stays equal while the word is in the field; a change means the host moved or cleared the field.
    private var wordStartBefore = ""

    let english = ProtlyLayoutService(alphabeticInputSet: .qwerty, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let korean = ProtlyLayoutService(alphabeticInputSet: .dubeolsik, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let koreanPlain = ProtlyLayoutService(alphabeticInputSet: .dubeolsikPlain, numericInputSet: .numeric, symbolicInputSet: .symbolic)

    private static let previousKey = "protly.previousLanguage"

    override var primaryLanguage: String? {
        get { "ko-KR" }  // KeyboardKit would report its English locale; protly is mainly Korean
        set {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup(for: KeyboardApp(name: "Protly"))

        let handler = ProtlyActionHandler(controller: self)
        handler.host = self
        services.actionHandler = handler

        // Haptics off: a keyboard cannot read the system Haptic Feedback switch, and the user keeps it off.
        state.feedbackContext.settings.isHapticFeedbackEnabled = false
        state.feedbackContext.hapticConfiguration = .disabled
        (services.calloutService as? Callouts.StandardCalloutService)?.feedbackService = nil

        session = TypingSession(previous: Self.loadPrevious())
        refreshMode()
        // The word lists take about 136 ms to load: once per process, off the main thread, Hangul rule until then.
        Task { [weak self] in
            let detector = await Self.detectorTask.value
            self?.setDetector(detector)
        }
    }

    /// viewDidLoad runs again for every host app; the extension process (and this load) usually survives.
    private static let detectorTask = Task.detached(priority: .userInitiated) { try? LanguageDetector.bundled() }

    private func setDetector(_ detector: LanguageDetector?) {
        session.detector = detector
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [unowned self] controller in
            ProtlyRoot(host: self, mode: mode, context: controller.state.keyboardContext)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setKeyboardCase(state.keyboardContext.preferredKeyboardCase)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The host keeps the marked word as text; forget it so the next key does not replace it.
        session.abandon()
        savePrevious()  // the abandoned word's language carries to the next message
        marked = ""
        refreshMode()
    }

    // MARK: Typing

    func typeLetter(_ letter: Character) {
        noticeFieldMoved()
        if !session.isComposing { wordStartBefore = textDocumentProxy.documentContextBeforeInput ?? "" }
        let kc = state.keyboardContext.keyboardCase
        let shift: Shift = kc.isUppercasedOrCapslocked ? (mode.manualShift || kc == .capsLocked ? .manual : .automatic) : .none
        apply(session.type(KeyEvent(letter, shift)))
        if kc == .uppercased {
            setKeyboardCase(.lowercased)  // one-shot shift, like Apple
            mode.manualShift = false
        }
        refreshMode()
    }

    /// true when the key was inside a word being typed.
    func backspaceInWord() -> Bool {
        guard let edit = session.backspace() else { return false }
        apply(edit)
        refreshMode()
        return true
    }

    func flipWord() {
        guard let edit = session.flip() else { return }
        apply(edit)
        savePrevious()
        refreshMode()
    }

    /// The host changed the field under protly (a chat app sent the message and cleared the field with the
    /// keyboard still up; the user tapped elsewhere in the text): drop the word being typed without editing the
    /// field, and stop a flip from deleting at a moved cursor.
    /// [UNVERIFIED] What `hasText` reports while only marked text is in the field. If Task 4.4 item 1 splits the
    /// first word of an empty field (each key starts a new word), drop the `!p.hasText` clause first.
    private func noticeFieldMoved() {
        let p = textDocumentProxy
        let before = p.documentContextBeforeInput ?? ""
        if session.isComposing {
            guard !p.hasText || before != wordStartBefore else { return }
            session.abandon()
            savePrevious()
            marked = ""
        } else if let tail = session.lastTail, !before.hasSuffix(tail) {
            session.forgetLast()
        } else {
            return
        }
        refreshMode()
    }

    /// End the word being typed before KeyboardKit touches the field.
    private func commitWord() {
        guard let edit = session.commit() else { return }
        apply(edit)
        savePrevious()
    }

    private func apply(_ edit: FieldEdit) {
        let proxy = textDocumentProxy
        let none = NSRange(location: 0, length: 0)
        switch edit {
        case .mark(""):
            // Clearing a mark makes hosts swallow the next delete: settle the jamo as text, then delete it.
            proxy.setMarkedText("", selectedRange: none)
            proxy.insertText(marked)
            for _ in marked { proxy.deleteBackward() }
            marked = ""
        case .mark(let text):
            proxy.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
            marked = text
        case .commit(let text):
            // unmarkText() followed by another edit in the same run-loop turn loses the word in every host tested.
            proxy.setMarkedText("", selectedRange: none)
            proxy.insertText(text)
            marked = ""
        case .replace(let count, let text):
            for _ in 0..<count { proxy.deleteBackward() }
            proxy.insertText(text)
        }
    }

    private func refreshMode() {
        let korean = session.keycapLanguage == .korean
        if mode.korean != korean { mode.korean = korean }
        if mode.alternative != session.alternative { mode.alternative = session.alternative }
    }

    private static func loadPrevious() -> Language? {
        switch UserDefaults.standard.string(forKey: previousKey) {
        case "korean": return .korean
        case "english": return .english
        default: return nil
        }
    }

    private func savePrevious() {
        guard let p = session.previous else { return }
        UserDefaults.standard.set(p == .korean ? "korean" : "english", forKey: Self.previousKey)
    }

    // MARK: KeyboardKit text calls: commit the word first

    override func insertText(_ text: String) {
        commitWord()
        super.insertText(text)
        session.noteInserted(text)
        refreshMode()
    }

    override func deleteBackward() {
        commitWord()
        session.forgetLast()
        super.deleteBackward()
        refreshMode()
    }

    override func deleteBackward(times: Int) {
        commitWord()
        session.forgetLast()
        super.deleteBackward(times: times)
        refreshMode()
    }

    override func adjustTextPosition(by offset: Int) {
        commitWord()
        session.forgetLast()
        super.adjustTextPosition(by: offset)
        refreshMode()
    }

    override func endSentence(withText text: String) {
        commitWord()
        session.forgetLast()
        super.endSentence(withText: text)
        refreshMode()
    }

    override func setKeyboardType(_ type: Keyboard.KeyboardType) {
        if case .emojis = type {
            commitWord()
            advanceToNextInputMode()  // Apple's Emoji keyboard is next in the list; its ABC key returns here
            return
        }
        super.setKeyboardType(type)
    }

    // MARK: Host callbacks

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        noticeFieldMoved()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        noticeFieldMoved()
    }

    override func textDidChangeAsync(_ textInput: UITextInput?) {
        // The proxy context excludes marked text, so autocap would see a sentence start mid-word.
        if session.isComposing { return }
        super.textDidChangeAsync(textInput)
    }
}

struct ProtlyRoot: View {
    unowned let host: KeyboardViewController
    @ObservedObject var mode: ProtlyMode
    @ObservedObject var context: KeyboardContext

    var body: some View {
        let doubled = mode.manualShift || context.keyboardCase == .capsLocked
        let service = mode.korean ? (doubled ? host.korean : host.koreanPlain) : host.english
        KeyboardView(
            layout: service.keyboardLayout(for: context),
            state: host.state,
            services: host.services,
            buttonContent: { params in
                if params.item.action == .space {
                    Color.clear  // Apple's space bar has no label
                } else {
                    params.view
                }
            },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { _ in EmptyView() },  // not KeyboardKit's placeholder: keeps the emoji key
            toolbar: { _ in ProtlyBar(mode: mode, flip: { [unowned host] in host.flipWord() }) }
        )
        .autocompleteToolbarStyle(.init(height: ProtlyGeometry.toolbarHeight))
        .keyboardViewStyle(.init(edgeInsets: EdgeInsets(top: 0, leading: 0, bottom: ProtlyGeometry.bottomInset, trailing: 0)))
        .keyboardButtonStyle(builder: { [context] params in
            var style = params.standardStyle(for: context)
            if case .shift = params.action, context.keyboardCase.isUppercasedOrCapslocked {
                style.backgroundColor = .white  // Apple: white key, black glyph
                style.foregroundColor = .black
            }
            return style
        })
    }
}
