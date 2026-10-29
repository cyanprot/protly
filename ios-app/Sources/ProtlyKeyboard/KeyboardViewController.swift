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
    /// The panel in place of the keys, nil = keys.
    @Published var panel: PanelState?
    /// The action that fits the field now (nil while typing or when the field is empty).
    @Published var draftMode: ActionMode?
    @Published var canUndo = false
    /// The clipboard holds text copied since protly last looked (checked without reading it).
    @Published var clipboardIsNew = false
    /// The bar's right slot: a fix or a completion for the word being typed. Only a tap puts it in.
    @Published var suggestion: String?
}

@objc(KeyboardViewController)
final class KeyboardViewController: KeyboardInputViewController {
    let mode = ProtlyMode()
    /// Not private(set): Words.swift fills its suggester.
    var session = TypingSession()
    /// Marked text currently in the field, mirrored here because the proxy's context excludes it.
    private var marked = ""
    /// The text before the word being typed, taken at its first key. The proxy's context excludes the mark,
    /// so it stays equal while the word is in the field; a change means the host moved or cleared the field.
    private var wordStartBefore = ""

    let english = ProtlyLayoutService(alphabeticInputSet: .qwerty, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let korean = ProtlyLayoutService(alphabeticInputSet: .dubeolsik, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let koreanPlain = ProtlyLayoutService(alphabeticInputSet: .dubeolsikPlain, numericInputSet: .numeric, symbolicInputSet: .symbolic)

    private static let previousKey = "protly.previousLanguage"
    private static let clipboardKey = "protly.clipboardChangeCount"
    private var actionTask: Task<Void, Never>?
    /// Text protly inserted and what it replaced, for Undo.
    private var lastInsert: (inserted: String, original: String, isSelection: Bool)?
    /// LearnedWords.changes at the last save (Words.swift). Per controller: each one loads its own copy.
    var savedChanges = 0

    override var primaryLanguage: String? {
        get { "ko-KR" }  // KeyboardKit would report its English locale; protly is mainly Korean
        set {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ProtlyHeight.pin(self)
        setup(for: KeyboardApp(name: "Protly"))

        let handler = ProtlyActionHandler(controller: self)
        handler.host = self
        services.actionHandler = handler

        // Haptics off: a keyboard cannot read the system Haptic Feedback switch, and the user keeps it off.
        state.feedbackContext.settings.isHapticFeedbackEnabled = false
        state.feedbackContext.hapticConfiguration = .disabled
        (services.calloutService as? Callouts.StandardCalloutService)?.feedbackService = nil
        // Autocap off: the user keeps it off, and a keyboard cannot read the system switch either.
        state.keyboardContext.settings.isAutocapitalizationEnabled = false

        session = TypingSession(previous: Self.loadPrevious())
        setUpWords()
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
        refreshMode()  // the word being typed may change language and suggestion
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [unowned self] controller in
            ProtlyRoot(host: self, mode: mode, context: controller.state.keyboardContext)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ProtlyHeight.presented(self)
        setKeyboardCase(state.keyboardContext.preferredKeyboardCase)
        refreshField()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The host keeps the marked word as text; forget it so the next key does not replace it.
        session.abandon()
        savePrevious()  // the abandoned word's language carries to the next message
        marked = ""
        actionTask?.cancel()
        mode.panel = nil
        endUndo()
        refreshMode()
    }

    // MARK: Typing

    func typeLetter(_ letter: Character) {
        endUndo()
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
        // Shift is spent, as on KeyboardKit's own path (this gesture skips its case change).
        if state.keyboardContext.keyboardCase == .uppercased { setKeyboardCase(.lowercased) }
        refreshMode()
        return true
    }

    func flipWord() {
        noticeFieldMoved()  // the field may have changed with no callback yet (a sent message, a moved cursor)
        guard let edit = session.flip() else { return }
        apply(edit)
        savePrevious()
        refreshMode()
    }

    /// The bar's right slot: the word becomes the suggestion, then a space typed like any other.
    func pickSuggestion() {
        let shown = mode.suggestion  // what the user tapped, before noticeFieldMoved can refresh the bar
        noticeFieldMoved()
        // If the suggestion changed since the bar showed it, do nothing.
        guard session.suggestion == shown, let edit = session.accept() else { return }
        apply(edit)
        savePrevious()
        insertText(" ")
    }

    /// The host changed the field under protly (a chat app sent the message and cleared the field with the
    /// keyboard still up; the user tapped elsewhere in the text): drop the word being typed without editing the
    /// field, and stop a flip from deleting at a moved cursor.
    /// `!p.hasText` holds with only marked text in the field: Sprint 4 item 1 typed a first word whole.
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

    // MARK: Actions (Translate / Polish / Read clipboard)

    /// requested nil = the protly key: the action that fits the field, or the clipboard when it is empty.
    func act(_ requested: ActionMode?) {
        commitWord()
        session.forgetLast()  // the field is about to change: the bar's flip must not reach into it
        refreshMode()
        // Every path below shows its own panel: a request still running must not replace it later.
        actionTask?.cancel()
        guard hasFullAccess else {
            mode.panel = .failed("Turn on Full Access in Settings to use protly actions", retry: requested ?? .in)
            return
        }
        if requested == .in {
            readClipboard()
            return
        }
        // The panel shows at once: a second tap during the field read cannot start a second request.
        mode.panel = .loading(requested ?? mode.draftMode ?? .in)
        actionTask = Task { [weak self] in
            guard let self else { return }
            let field = await FieldText.read(textDocumentProxy)
            guard !Task.isCancelled else { return }
            guard let field else {
                mode.panel = nil
                if requested == nil { readClipboard() }
                return
            }
            // The bar's mode came from the whole field; a selection gets its own.
            let action = requested == nil || field.isSelection ? ActionAPI.mode(forDraft: field.text) : requested!
            // Text left after the cursor = only a prefix was read: Insert would glue the result to the rest.
            if !field.isSelection, !(textDocumentProxy.documentContextAfterInput ?? "").isEmpty {
                mode.panel = .failed("Could not read the whole text. Select all, then tap again.", retry: action)
                return
            }
            run(action, text: field.text, original: field.text, isSelection: field.isSelection)
        }
    }

    /// Reading the string shows the Allow Paste prompt: only ever on a tap.
    private func readClipboard() {
        let pb = UIPasteboard.general
        UserDefaults.standard.set(pb.changeCount, forKey: Self.clipboardKey)
        mode.clipboardIsNew = false
        guard let text = pb.string, !text.isEmpty else {
            let message = pb.hasStrings ? "Paste was not allowed." : "Copy a message first."
            mode.panel = .failed(message, retry: .in)
            return
        }
        // The container app's "about me" note arrives this way (no App Group). Any app can copy the marker, so the
        // note is only shown here; Save on the panel (insertResult) keeps it.
        switch AboutMe.parse(clipboard: text) {
        case .notAboutMe:
            run(.in, text: text, original: "", isSelection: false)
        case .note(let note):
            mode.panel = .confirmNote(note, shownAt: ProcessInfo.processInfo.systemUptime)
        case .tooLong(let count):
            mode.panel = .notice("About me is \(count) characters. Shorten it to \(AboutMe.cap) in the Protly app.")
        case .hiddenCharacters:
            mode.panel = .notice("About me has hidden characters. Retype it in the Protly app.")
        }
    }

    private func run(_ action: ActionMode, text: String, original: String, isSelection: Bool) {
        mode.panel = .loading(action)
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            let result = await ActionClient.run(action, text: text)
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let r):
                mode.panel = .result(action, r, original: original, isSelection: isSelection)
            case .failure(let e):
                mode.panel = .failed(e.message, retry: action)
            }
        }
    }

    func insertResult() {
        // Save on the About me confirm panel: the only way a clipboard note is kept. A tap in the first
        // AboutMe.saveDelay seconds is dropped (it falls to the guard below, which returns).
        let now = ProcessInfo.processInfo.systemUptime
        if case let .confirmNote(note, shownAt) = mode.panel, AboutMe.canSave(shownAt: shownAt, now: now) {
            UserDefaults.standard.set(note, forKey: AboutMe.defaultsKey)
            mode.panel = .notice(AboutMe.savedText(for: note))
            return
        }
        guard case let .result(action, r, original, isSelection) = mode.panel else { return }
        // The user may have moved the cursor or edited while the request ran: never delete the wrong text.
        let p = textDocumentProxy
        let unchanged = isSelection
            ? p.selectedText == original
            : FieldGuard.canReplace(
                original, before: p.documentContextBeforeInput ?? "", after: p.documentContextAfterInput ?? "")
        guard unchanged else {
            mode.panel = .failed("The text changed. Try again.", retry: action)
            return
        }
        FieldText.replace(original, isSelection: isSelection, with: r.translation, p)
        lastInsert = (r.translation, original, isSelection)
        mode.canUndo = true
        mode.panel = nil
        refreshField()
    }

    func undoInsert() {
        guard let l = lastInsert else { return }
        guard FieldGuard.canUndo(l.inserted, before: textDocumentProxy.documentContextBeforeInput ?? "") else {
            endUndo()  // the cursor moved or the text changed since Insert
            return
        }
        for _ in l.inserted { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(l.original)
        endUndo()
        refreshField()
    }

    func closePanel() {
        actionTask?.cancel()
        mode.panel = nil
    }

    private func endUndo() {
        lastInsert = nil
        if mode.canUndo { mode.canUndo = false }
    }

    /// Which action the bar offers for the field text around the cursor, and whether new text was copied.
    private func refreshField() {
        let p = textDocumentProxy
        let text = (p.documentContextBeforeInput ?? "") + (p.documentContextAfterInput ?? "")
        let next: ActionMode? = session.isComposing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : ActionAPI.mode(forDraft: text)
        if mode.draftMode != next { mode.draftMode = next }

        // changeCount and hasStrings never show the Allow Paste prompt; reading the string does.
        // changeCount is cheap, so it goes first; hasStrings only runs after a change.
        let pb = UIPasteboard.general
        let d = UserDefaults.standard
        if d.object(forKey: Self.clipboardKey) == nil { d.set(pb.changeCount, forKey: Self.clipboardKey) }  // first run: old clipboard is not new
        // Only an empty field offers the clipboard, so the cheap checks skip the pasteboard on most keys.
        let isNew = !session.isComposing
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pb.changeCount != d.integer(forKey: Self.clipboardKey) && pb.hasStrings
        if mode.clipboardIsNew != isNew { mode.clipboardIsNew = isNew }
    }

    /// Not private: Words.swift calls it when the system lexicon arrives.
    func refreshMode() {
        let korean = session.keycapLanguage == .korean
        if mode.korean != korean { mode.korean = korean }
        if mode.alternative != session.alternative { mode.alternative = session.alternative }
        refreshWords()
        refreshField()
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
        endUndo()
        refreshMode()
    }

    override func deleteBackward() {
        commitWord()
        session.forgetLast()
        endUndo()
        super.deleteBackward()
        refreshMode()
    }

    override func deleteBackward(times: Int) {
        commitWord()
        session.forgetLast()
        endUndo()
        super.deleteBackward(times: times)
        refreshMode()
    }

    override func adjustTextPosition(by offset: Int) {
        commitWord()
        session.forgetLast()
        endUndo()
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
            act(nil)  // the protly key; iOS's own bottom-left key opens Emoji
            return
        }
        super.setKeyboardType(type)
    }

    // MARK: Host callbacks

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        noticeFieldMoved()
        refreshField()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        noticeFieldMoved()
        refreshField()
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
        // A late host callback can lower the case while manualShift is still set: trust the case too.
        let doubled = context.keyboardCase == .capsLocked || (mode.manualShift && context.keyboardCase == .uppercased)
        let service = mode.korean ? (doubled ? host.korean : host.koreanPlain) : host.english
        let layout = service.keyboardLayout(for: context)
        let layoutHeight = layout.totalHeight
        KeyboardView(
            layout: layout,
            state: host.state,
            services: host.services,
            buttonContent: { params in
                if params.item.action == .space {
                    Color.clear  // Apple's space bar has no label
                } else if params.item.action == .keyboardType(.emojis) {
                    Image(systemName: "character.bubble").font(.system(size: 21))  // the protly key
                } else {
                    params.view
                }
            },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { _ in EmptyView() },  // not KeyboardKit's placeholder: keeps the emoji key
            toolbar: { _ in
                ProtlyBar(
                    mode: mode,
                    flip: { [unowned host] in host.flipWord() },
                    act: { [unowned host] in host.act($0) },
                    undo: { [unowned host] in host.undoInsert() },
                    pick: { [unowned host] in host.pickSuggestion() }
                )
            }
        )
        .overlay(alignment: .bottom) {
            if let panel = mode.panel {
                // Same height as the key area: the keyboard never grows.
                PanelView(
                    state: panel,
                    insert: { [unowned host] in host.insertResult() },
                    close: { [unowned host] in host.closePanel() },
                    retry: { [unowned host] in host.act($0) }
                )
                .frame(height: layoutHeight)
            }
        }
        // Outside the view: KeyboardKit sizes keys from the width it is given, and its own edgeInsets
        // only pad inside a fixed frame, which moves nothing.
        .padding(.horizontal, ProtlyGeometry.sideInset)
        .frame(maxHeight: .infinity, alignment: .bottom)  // ProtlyHeight may drop the pin below the content's height
        .autocompleteToolbarStyle(.init(height: ProtlyGeometry.toolbarHeight))
        .keyboardButtonStyle(builder: { [context] params in
            var style = params.standardStyle(for: context)
            if case .shift = params.action {
                // Apple iOS 26: an active shift is the same gray key with the letters' arrow color.
                // KeyboardKit draws it black, for its older white key.
                style.foregroundColor = KeyboardAction.character("a").standardButtonForegroundColor(for: context)
            }
            return style
        })
    }
}
