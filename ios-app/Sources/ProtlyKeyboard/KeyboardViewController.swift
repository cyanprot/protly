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
    /// The alternative is a listed word in its language: drawn in the primary color, else dimmed (B4).
    @Published var alternativeIsWord = true
    /// The panel in place of the keys, nil = keys.
    @Published var panel: PanelState?
    /// The progress strip in place of the bar while a call runs, or after it failed before any text; nil = the bar.
    /// Changes at the start and the end of a call only: the streamed text is in ResultFeed.
    @Published var strip: StripState?
    /// The bar's center slot (nil = empty) and what the protly key runs. ProtlyCore decides both from the field text
    /// (BarAction), the same way the request is built, so a label never names another target.
    @Published var center: BarAction?
    @Published var protlyKey: BarAction = .read
    /// Full Access is on: without it the pill is an outlined lock and a tap explains why.
    @Published var fullAccess = true
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
    /// The word being typed as Protly wrote it into the field (plain text, no marked text), "" between words.
    private var written = ""
    /// Protly's model of the text before the cursor from its own writes: whether the field still holds the word.
    private var watch = FieldWatch(known: false)

    let english = ProtlyLayoutService(alphabeticInputSet: .qwerty, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let korean = ProtlyLayoutService(alphabeticInputSet: .dubeolsik, numericInputSet: .numeric, symbolicInputSet: .symbolic)
    let koreanPlain = ProtlyLayoutService(alphabeticInputSet: .dubeolsikPlain, numericInputSet: .numeric, symbolicInputSet: .symbolic)

    private static let previousKey = "protly.previousLanguage"
    private static let clipboardKey = "protly.clipboardChangeCount"
    private var actionTask: Task<Void, Never>?
    /// The open result card's streamed text: only ResultCard reads it.
    let feed = ResultFeed()
    /// Numbers the calls: a new number restarts the strip's 8 s line and makes a new card.
    private var calls = 0
    /// What the field reads moved the cursor over, for Cancel (P6).
    private var cursorReturn = CursorReturn()
    /// Text protly inserted and what it replaced, for Undo.
    private var lastInsert: (inserted: String, original: String, isSelection: Bool)?
    /// LearnedWords.changes at the last save (Words.swift). Per controller: each one loads its own copy.
    var savedChanges = 0

    /// Follows the keycaps, so dictation listens in the language on the keys (it stayed Korean before).
    /// KeyboardKit's setter is ignored: it would report its own locale.
    override var primaryLanguage: String? {
        get { session.keycapLanguage == .korean ? "ko-KR" : "en-US" }
        set {}
    }

    deinit {
        actionTask?.cancel()
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
        // Space trackpad (typing-fixes 003): ProtlyActionHandler moves the cursor with SpaceTrackpad, so KeyboardKit's
        // drag handler runs only if that path has no host. Even then a thumb drifting up must never freeze the
        // cursor (R1): KeyboardKit dropped every step 50 pt above or below the start.
        services.spaceDragGestureHandler.verticalThreshold = .greatestFiniteMagnitude
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
        // The word is already plain text in the field: only the session state goes, so the next key starts a new
        // word. The abandoned word's language carries to the next message.
        abandonWord()
        // Hiding mid-call counts as Cancel: the call stops and the cursor goes back too.
        restoreCursor()
        if mode.panel != nil { mode.panel = nil }
        if mode.strip != nil { mode.strip = nil }  // also stops the glow
        feed.reset()
        endUndo()
        refreshMode()
    }

    // MARK: Typing

    func typeLetter(_ letter: Character) {
        endUndo()
        noticeFieldMoved()
        let kc = state.keyboardContext.keyboardCase
        let shift: Shift = kc.isUppercasedOrCapslocked ? (mode.manualShift || kc == .capsLocked ? .manual : .automatic) : .none
        let key = KeyEvent(letter, shift)
        if !session.isComposing { beginWord() }
        if !apply(session.type(key)) {
            // The field moved under the word: it stays as typed, and this key (already taken by the abandoned
            // word) starts a new one, so it is not lost.
            beginWord()
            apply(session.type(key))
        }
        if kc == .uppercased {
            setKeyboardCase(.lowercased)  // one-shot shift, like Apple
            mode.manualShift = false
        }
        refreshMode()
    }

    /// true when the key was inside a word being typed. false when no word is typed, or the field moved under the
    /// word (it is abandoned): KeyboardKit then deletes one character normally.
    func backspaceInWord() -> Bool {
        guard let edit = session.backspace() else { return false }
        guard apply(edit) else { return false }
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
        guard apply(edit) else {
            refreshMode()  // the field moved: the word was abandoned, nothing written
            return
        }
        savePrevious()
        insertText(" ")
    }

    /// The host changed the field under protly (a chat app sent the message and cleared the field with the
    /// keyboard still up; the user tapped into the word or selected it): drop the word being typed without
    /// editing the field, and stop a flip from deleting at a moved cursor. The rules are FieldWatch's.
    /// hasText is not used: it was for marked text, which the context excluded (Sprint 4 item 1). The word is plain
    /// text now, and WebKit reports hasText false right after each edit, which would split every word.
    /// Called from host callbacks: it only reads the field and decides, never writes (KeyboardSourceRulesTests).
    private func noticeFieldMoved() {
        switch watch.decide(observed(), composing: session.isComposing, lastTail: session.lastTail, now: now) {
        case .keep: return
        case .abandon: abandonWord()
        case .forgetLast: session.forgetLast()
        }
        refreshMode()
    }

    /// The word stays in the field as typed; Protly stops changing it and no longer trusts its model of the field.
    private func abandonWord() {
        session.abandon()
        savePrevious()
        written = ""
        watch.forget()
    }

    /// The word's first key, before anything is written: where the word starts.
    private func beginWord() {
        watch.begin(observed(), now: now)
    }

    private func observed() -> FieldWatch.Observed {
        let p = textDocumentProxy
        return FieldWatch.Observed(
            before: p.documentContextBeforeInput ?? "", after: p.documentContextAfterInput ?? "",
            selected: p.selectedText ?? "", hasText: p.hasText)
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// End the word being typed before KeyboardKit touches the field. Returns the word as the commit left it in the
    /// field, nil when nothing was committed (no word, or the field moved under it and it was abandoned).
    @discardableResult
    private func commitWord() -> String? {
        guard let edit = session.commit() else { return nil }
        let wrote = apply(edit)
        savePrevious()
        guard wrote, case .commit(let text) = edit else { return nil }
        return text
    }

    /// Writes the edit as plain text: the word changes by deleting the characters after the part that stays and
    /// inserting the new tail (PlainWord). Always the proxy's own calls, never this controller's insertText or
    /// deleteBackward overrides, which commit first. false when the field moved under the word: nothing is
    /// written and the word is abandoned.
    @discardableResult
    private func apply(_ edit: FieldEdit) -> Bool {
        let step = PlainWord.step(edit, written: written)
        guard step.deleting > 0 || !step.inserting.isEmpty else {
            written = step.written  // a commit that reads as typed: nothing to send
            return true
        }
        // Before any write over the word: the field must still hold it.
        if !written.isEmpty,
           watch.decide(observed(), composing: true, lastTail: nil, now: now) == .abandon {
            abandonWord()
            return false
        }
        let proxy = textDocumentProxy
        for _ in 0..<step.deleting { proxy.deleteBackward() }
        if !step.inserting.isEmpty { proxy.insertText(step.inserting) }
        watch.wrote(deleting: step.deleting, inserting: step.inserting, at: now)
        written = step.written
        return true
    }

    // MARK: Actions (Translate / Polish / Read clipboard)

    /// requested nil = the protly key: the action that fits the field, or the clipboard when it is empty.
    func act(_ requested: ActionMode?) {
        // While a call runs, another tap does nothing (B10): the strip has no action, and the protly key is still live.
        if let strip = mode.strip, strip.error == nil { return }
        commitWord()
        session.forgetLast()  // the field is about to change: the bar's flip must not reach into it
        watch.forget()  // reading the field moves the cursor
        refreshMode()
        // Every path below shows its own strip or panel: a request still running must not replace it later.
        actionTask?.cancel()
        if mode.panel != nil { mode.panel = nil }
        feed.reset()
        guard hasFullAccess else {
            // F1: say why instead of a failed call (the bar shows the outlined lock pill).
            mode.strip = nil
            mode.panel = .notice(
                "Translate, Polish and Read need Full Access: Settings > General > Keyboard > Keyboards > Protly > Allow Full Access")
            return
        }
        if requested == .in {
            readClipboard()
            return
        }
        // The strip shows at once, labeled as the bar was: a second tap during the field read starts nothing.
        let action = requested ?? mode.protlyKey.actionMode ?? .in
        let tapped = [mode.center, mode.protlyKey].compactMap { $0 }.first { $0.actionMode == action }
        let call = nextCall()
        mode.strip = StripState(call: call, action: action, label: tapped ?? BarAction.call(action, text: ""))
        actionTask = Task { [weak self] in
            guard let self else { return }
            cursorReturn.begin()
            let field = await FieldText.read(textDocumentProxy) { [weak self] in self?.cursorReturn.moved(over: $0) }
            cursorReturn.end()  // also after a cancel: the moves made so far count
            guard !Task.isCancelled else { return }
            guard let field else {
                mode.strip = nil
                if requested == nil { readClipboard() }
                return
            }
            if field.isSelection { cursorReturn.clear() }
            // The action comes from the text read here (the whole field or the selection), not from the bar's view of it.
            let action = ActionAPI.mode(forDraft: field.text)
            // Text left after the cursor = only a prefix was read: Replace would glue the result to the rest.
            if !field.isSelection, !(textDocumentProxy.documentContextAfterInput ?? "").isEmpty {
                mode.strip = nil
                mode.panel = .failed("Could not read the whole text. Select all, then tap again.", retry: action)
                return
            }
            run(action, text: field.text, original: field.text, isSelection: field.isSelection, call: call)
        }
    }

    private func nextCall() -> Int {
        calls += 1
        return calls
    }

    /// Reading the string shows the Allow Paste prompt: only ever on a tap.
    private func readClipboard() {
        cursorReturn.clear()  // Read does not touch the field
        if mode.strip != nil { mode.strip = nil }
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

    /// One call: the strip at once, the card at the first text, the result or the error at the end (design Part 3).
    private func run(_ action: ActionMode, text: String, original: String, isSelection: Bool, call: Int? = nil) {
        let call = call ?? nextCall()
        let label = BarAction.call(action, text: text)
        if mode.panel != nil { mode.panel = nil }
        feed.reset()
        // From act() the strip is already up for this call: one write at most.
        let strip = StripState(call: call, action: action, label: label)
        if mode.strip != strip { mode.strip = strip }
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            // self is bound per update, never before the loop: a torn-down controller is not held for up to 90 s. The
            // cancel check stops a late update from bringing a card back after Cancel or after a Retry replaced this task.
            for await update in ActionClient.run(action, text: text) {
                guard let self, !Task.isCancelled else { return }
                show(update, card: CardState(call: call, action: action, label: label, original: original,
                                             isSelection: isSelection, shownAt: now))
            }
            // The stream ended with no result (the system cancelled the download): never leave the call hanging.
            guard let self, !Task.isCancelled, let strip = mode.strip, strip.call == call, strip.error == nil else { return }
            show(.failed(ActionError(.network)), card: CardState(call: call, action: action, label: label,
                                                                 original: original, isSelection: isSelection, shownAt: now))
        }
    }

    /// `card` is the card to open if none is open yet. mode.panel changes at the first text and at the end only.
    private func show(_ update: ActionUpdate, card fresh: CardState) {
        switch update {
        case .partial(let text):
            feed.partial = text
            if openCard != nil { return }
            mode.panel = .card(fresh)
        case .done(let result):
            feed.partial = result.translation
            feed.back = result.backTranslation
            var card = openCard ?? fresh
            card.phase = .done
            // P10: typed or moved during the call: the result stays, only Copy is offered.
            card.copyOnly = card.action != .in && !fieldHolds(card.original, isSelection: card.isSelection)
            mode.strip = nil
            mode.panel = .card(card)
        case .failed(let error):
            guard var card = openCard else {
                // No text yet: the error replaces the strip's label, the keys stay, no card opens.
                mode.strip?.error = error
                return
            }
            // Text on screen: it stays, dimmed, with the error line under it.
            feed.failed = error
            card.phase = .failed
            mode.strip = nil
            mode.panel = .card(card)
        }
    }

    private var openCard: CardState? {
        if case .card(let card) = mode.panel { return card }
        return nil
    }

    /// The field still holds what the read returned (the selection, or the whole text with the cursor at its end).
    private func fieldHolds(_ original: String, isSelection: Bool) -> Bool {
        let p = textDocumentProxy
        return isSelection
            ? p.selectedText == original
            : FieldGuard.canReplace(original, before: p.documentContextBeforeInput ?? "", after: p.documentContextAfterInput ?? "")
    }

    /// Replace (Translate, Polish) and Insert (Read) on the card, and Save on the About me confirm panel: the panel's
    /// insert button is the only caller.
    func insertResult() {
        // Save on the About me confirm panel: the only way a clipboard note is kept. A tap in the first
        // AboutMe.saveDelay seconds is dropped (it falls to the guard below, which returns).
        let now = ProcessInfo.processInfo.systemUptime
        if case let .confirmNote(note, shownAt) = mode.panel, AboutMe.canSave(shownAt: shownAt, now: now) {
            UserDefaults.standard.set(note, forKey: AboutMe.defaultsKey)
            mode.panel = .notice(AboutMe.savedText(for: note))
            return
        }
        guard var card = openCard, card.primary != nil, AboutMe.canSave(shownAt: card.shownAt, now: now) else { return }
        let result = feed.partial
        let p = textDocumentProxy
        if card.action == .in {
            // Read: the reply goes in at the cursor; Undo takes it out again.
            p.insertText(result)
            lastInsert = (result, "", false)
        } else {
            // The user may have moved the cursor or edited since: never delete the wrong text (P10).
            guard fieldHolds(card.original, isSelection: card.isSelection) else {
                card.copyOnly = true
                mode.panel = .card(card)
                return
            }
            FieldText.replace(card.original, isSelection: card.isSelection, with: result, p)
            lastInsert = (result, card.original, card.isSelection)
        }
        cursorReturn.clear()
        watch.forget()
        mode.canUndo = true
        mode.panel = nil
        feed.reset()
        refreshField()
    }

    /// Copy on the card: the one write to the pasteboard. false when the tap came too soon after the card appeared.
    func copyResult() -> Bool {
        guard let card = openCard, card.phase != .streaming, !feed.partial.isEmpty,
              AboutMe.canSave(shownAt: card.shownAt, now: now) else { return false }
        let pb = UIPasteboard.general
        pb.string = feed.partial
        // Protly's own copy is not new text: the bar must not offer to Read it.
        UserDefaults.standard.set(pb.changeCount, forKey: Self.clipboardKey)
        refreshField()
        return true
    }

    /// The protly key runs exactly what its symbol shows (K1): symbol and action are the same BarAction value.
    func runProtlyKey() {
        if mode.protlyKey == .undo {
            undoInsert()
        } else {
            act(nil)
        }
    }

    func undoInsert() {
        guard let l = lastInsert else { return }
        guard FieldGuard.canUndo(l.inserted, before: textDocumentProxy.documentContextBeforeInput ?? "") else {
            endUndo()  // the cursor moved or the text changed since Insert
            refreshField()  // the bar stops offering Undo
            return
        }
        for _ in l.inserted { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(l.original)
        watch.forget()
        endUndo()
        refreshField()
    }

    /// The strip's xmark, the card's Cancel or Done, and every other panel's close.
    func closePanel() {
        restoreCursor()
        if mode.panel != nil { mode.panel = nil }
        if mode.strip != nil { mode.strip = nil }
        feed.reset()
        refreshField()
    }

    /// P6: stop the call, then put the cursor back where it was before the reads moved it, while the text they moved
    /// over is still just before it. Works mid-read too: the moves made so far are recorded.
    private func restoreCursor() {
        actionTask?.cancel()
        actionTask = nil
        cursorReturn.end()
        let back = cursorReturn.back(before: textDocumentProxy.documentContextBeforeInput ?? "")
        cursorReturn.clear()
        guard back > 0 else { return }
        FieldText.restore(back, textDocumentProxy)
        watch.forget()
    }

    private func endUndo() {
        lastInsert = nil
        if mode.canUndo { mode.canUndo = false }
    }

    /// Which action the bar and the protly key offer for the field text around the cursor, and whether new text was
    /// copied. Since typing-fixes 001 the word being typed is plain text in the context, so the action stays
    /// visible while a word is typed.
    private func refreshField() {
        let p = textDocumentProxy
        let text = (p.documentContextBeforeInput ?? "") + (p.documentContextAfterInput ?? "")

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

        // @Published fires on every write; an unchanged write would rebuild the keyboard on each key.
        let center = BarAction.center(text: text, canUndo: mode.canUndo, clipboardIsNew: isNew)
        if mode.center != center { mode.center = center }
        let key = center ?? .read  // BarAction.protlyKey, without a second scan of the field
        if mode.protlyKey != key { mode.protlyKey = key }
        if mode.fullAccess != hasFullAccess { mode.fullAccess = hasFullAccess }
    }

    /// Not private: Words.swift calls it when the system lexicon arrives.
    func refreshMode() {
        let korean = session.keycapLanguage == .korean
        if mode.korean != korean { mode.korean = korean }
        if mode.alternative != session.alternative { mode.alternative = session.alternative }
        let isWord = session.alternativeIsWord
        if mode.alternativeIsWord != isWord { mode.alternativeIsWord = isWord }
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
        commitWord()  // Return after a word: the word is already in the field, so only "\n" follows it
        let overSelection = proxyHasSelection
        super.insertText(text)
        noteKeyboardKitWrite(deleting: 0, inserting: text, overSelection: overSelection)
        session.noteInserted(text)
        endUndo()
        refreshMode()
    }

    override func deleteBackward() {
        commitWord()
        session.forgetLast()
        endUndo()
        let overSelection = proxyHasSelection
        super.deleteBackward()
        // One Character, unless KeyboardKit deletes a word or a sentence at a time: then the model is lost.
        if services.keyboardBehavior.backspaceRange == .character {
            noteKeyboardKitWrite(deleting: 1, inserting: "", overSelection: overSelection)
        } else {
            watch.forget()
        }
        refreshMode()
    }

    override func deleteBackward(times: Int) {
        commitWord()
        session.forgetLast()
        endUndo()
        let overSelection = proxyHasSelection
        super.deleteBackward(times: times)
        noteKeyboardKitWrite(deleting: times, inserting: "", overSelection: overSelection)
        refreshMode()
    }

    private var proxyHasSelection: Bool { !(textDocumentProxy.selectedText ?? "").isEmpty }

    /// A write through KeyboardKit, outside a word. Over a selection it replaced text the model never saw.
    private func noteKeyboardKitWrite(deleting: Int, inserting: String, overSelection: Bool) {
        if overSelection {
            watch.forget()
            return
        }
        watch.wrote(deleting: deleting, inserting: inserting, at: now)
    }

    override func adjustTextPosition(by offset: Int) {
        commitWord()
        session.forgetLast()
        endUndo()
        super.adjustTextPosition(by: offset)
        watch.forget()  // the cursor moved
        refreshMode()
    }

    /// Space became the trackpad (typing-fixes 003): end the word being typed (the commit can change its reading),
    /// then snapshot the text around the cursor for SpaceTrackpad. The text before the cursor is read before the
    /// commit and the commit applied to it, because a read right after the commit may not show it yet. As at any
    /// cursor move, the bar's flip and Undo end here; the moves themselves go through adjustTextPosition below.
    func beginSpaceDrag() -> SpaceTrackpad {
        let p = textDocumentProxy
        let context = p.documentContextBeforeInput ?? ""
        let after = p.documentContextAfterInput ?? ""
        let word = written
        let committed = commitWord()
        session.forgetLast()
        endUndo()
        refreshMode()
        return SpaceTrackpad(
            before: SpaceTrackpad.textBefore(context: context, written: word, committed: committed), after: after)
    }

    override func endSentence(withText text: String) {
        commitWord()
        session.forgetLast()
        super.endSentence(withText: text)
        watch.forget()  // KeyboardKit may delete a space first
        refreshMode()
    }

    override func setKeyboardType(_ type: Keyboard.KeyboardType) {
        if case .emojis = type {
            runProtlyKey()  // the protly key; iOS's own bottom-left key opens Emoji
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
}

struct ProtlyRoot: View {
    unowned let host: KeyboardViewController
    @ObservedObject var mode: ProtlyMode
    @ObservedObject var context: KeyboardContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // The protly key: the symbol of what a tap runs, in the pill's accent (keyboardButtonStyle below).
                    Image(systemName: mode.protlyKey.keySymbol).font(.system(size: 21))
                } else {
                    params.view
                }
            },
            // The space trackpad starts after a shorter hold (R3); other keys keep KeyboardKit's 0.5 s.
            buttonView: { params in
                let view = params.view.keyboardButtonGestureConfiguration(
                    params.item.action == .space ? .init(longPressDelay: SpaceTrackpad.longPressDelay) : .standard)
                if params.item.action == .keyboardType(.emojis) {
                    // The protly key's spoken name is its action (D6 exception; KeyboardKit says "Keyboard Type -
                    // emojis"). KeyboardKit makes each key one element that ignores its content's labels, and its own
                    // label sits inside, so the key's accessibility is replaced, not relabeled. Drawing and gestures
                    // stay KeyboardKit's.
                    view.accessibilityRepresentation {
                        Button(mode.protlyKey.spokenLabel) { [unowned host] in host.runProtlyKey() }
                    }
                } else {
                    view
                }
            },
            collapsedView: { $0.view },
            emojiKeyboard: { _ in EmptyView() },  // not KeyboardKit's placeholder: keeps the emoji key
            toolbar: { _ in
                if let strip = mode.strip {
                    ProgressStrip(
                        state: strip,
                        scheme: context.colorScheme,
                        close: { [unowned host] in host.closePanel() },
                        retry: { [unowned host] in host.act($0) }
                    )
                } else {
                    ProtlyBar(
                        mode: mode,
                        scheme: context.colorScheme,
                        flip: { [unowned host] in host.flipWord() },
                        act: { [unowned host] in host.act($0) },
                        undo: { [unowned host] in host.undoInsert() },
                        pick: { [unowned host] in host.pickSuggestion() }
                    )
                }
            }
        )
        .overlay(alignment: .bottom) {
            // The animation sits on the always-present container, so the panel's removal animates too.
            ZStack {
                if let panel = mode.panel {
                    // Same height as the key area: the keyboard never grows.
                    PanelView(
                        state: panel,
                        feed: host.feed,
                        insert: { [unowned host] in host.insertResult() },
                        copy: { [unowned host] in host.copyResult() },
                        close: { [unowned host] in host.closePanel() },
                        retry: { [unowned host] in host.act($0) }
                    )
                    .frame(height: layoutHeight)
                    // The card grows down from the strip over the keys; a crossfade under Reduce Motion.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.3, bounce: 0), value: mode.panel == nil)
            // A card on its way out never takes a tap meant for the keys.
            .allowsHitTesting(mode.panel != nil)
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
            if case .keyboardType(.emojis) = params.action {
                // The protly key in the pill's accent (K1): tint only, Apple's key shape, size and pressed look stay.
                style.foregroundColor = Brand.pillFill(context.colorScheme)
            }
            return style
        })
    }
}
