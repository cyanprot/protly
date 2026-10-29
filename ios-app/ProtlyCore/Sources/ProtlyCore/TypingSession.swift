// The word being typed and the word just committed, as edits for the text field.
// The keyboard owns no text logic: it feeds keys in and applies the returned edits.

public enum FieldEdit: Sendable, Equatable {
    /// Show this as marked (composing) text, replacing the current marked text. "" clears it.
    case mark(String)
    /// The word is final: replace the marked text with this plain text.
    case commit(String)
    /// Delete this many characters before the cursor, then insert the text (flipping a committed word).
    case replace(deleting: Int, inserting: String)
}

public struct TypingSession: Sendable {
    public private(set) var keys: [KeyEvent] = []
    /// Language of the word being typed (or of the last word, when nothing is being typed).
    public private(set) var language: Language
    /// Language of the last committed word: the `previous` of the next decision.
    public private(set) var previous: Language?
    /// The word lists load in the background; until then a Hangul-only rule decides.
    public var detector: LanguageDetector?
    /// Learned words and the system lexicon, for the bar's suggestion. Flips teach it.
    public var suggester = Suggester()

    private var forced: Language?  // the user flipped the word being typed
    private var last: (keys: [KeyEvent], text: String, language: Language, after: String)?

    public init(detector: LanguageDetector? = nil, previous: Language? = nil) {
        self.detector = detector
        self.previous = previous
        self.language = previous ?? .korean
    }

    public var isComposing: Bool { !keys.isEmpty }

    /// Keycaps to show: the word being typed, else the previous word's language, Korean at a message start.
    public var keycapLanguage: Language { isComposing ? language : (previous ?? .korean) }

    /// The other reading of the word being typed, or of the word just committed (for the bar).
    public var alternative: String? {
        if isComposing { return Self.render(keys, as: language.other) }
        return last.map { Self.render($0.keys, as: $0.language.other) }
    }

    /// The committed word plus what was typed after it, while it can still be flipped. The keyboard checks
    /// that the field still ends with it before a flip deletes anything.
    public var lastTail: String? { last.map { $0.text + $0.after } }

    /// For the bar's right slot while a word is typed: a fix (typo, contraction, text replacement) ahead of a
    /// completion. Only a tap puts it in (`accept`). A flipped word gets no fix: the user chose its reading.
    public var suggestion: String? {
        guard isComposing else { return nil }
        if forced == nil, let r = suggester.fix(keys, as: language, lists: detector) { return r }
        return suggester.completion(keys, as: language, lists: detector)
    }

    public mutating func type(_ key: KeyEvent) -> FieldEdit {
        keys.append(key)
        last = nil
        language = forced ?? decide(complete: false)
        return .mark(Self.render(keys, as: language))
    }

    /// nil when no word is being typed: the keyboard deletes normally, so the last word can no longer be flipped.
    public mutating func backspace() -> FieldEdit? {
        guard !keys.isEmpty else {
            last = nil
            return nil
        }
        keys.removeLast()
        if keys.isEmpty {
            forced = nil
            language = previous ?? .korean
            return .mark("")
        }
        language = forced ?? decide(complete: false)
        return .mark(Self.render(keys, as: language))
    }

    /// End the word (space, punctuation, return, cursor move). nil when no word is being typed.
    public mutating func commit() -> FieldEdit? {
        guard !keys.isEmpty else { return nil }
        let decided = decide(complete: true)
        let lang = forced ?? decided
        let text = Self.render(keys, as: lang)
        if lang != decided { suggester.learned.learn(text, as: lang) }  // flipped while typing: teach the reading
        last = (keys, text, lang, "")
        previous = lang
        language = lang
        keys = []
        forced = nil
        return .commit(text)
    }

    /// The bar's suggestion was tapped: the word becomes it. The keyboard then types a space. A pick alone teaches
    /// nothing (a pick of 해 for `g` would teach Korean "go"); after a flip while typing, the picked word is taught
    /// in the language the user flipped to, as `commit` would teach the flip.
    public mutating func accept() -> FieldEdit? {
        guard let s = suggestion else { return nil }
        if let forced, forced != decide(complete: true) { suggester.learned.learn(s, as: forced) }
        previous = language
        keys = []
        forced = nil
        last = nil
        return .commit(s)
    }

    /// The keyboard inserted text right after a commit (the space). Flipping still reaches the word.
    public mutating func noteInserted(_ text: String) {
        last?.after += text
    }

    /// Something else happened (delete, cursor move, field change): the committed word can no longer be flipped.
    public mutating func forgetLast() { last = nil }

    /// The field changed under us (keyboard hidden, message sent, other field): drop the word without editing
    /// the field. The word stays in the field (or was just sent) in its language, so that becomes `previous`.
    public mutating func abandon() {
        if isComposing { previous = language }
        keys = []
        forced = nil
        last = nil
        language = previous ?? .korean
    }

    /// Flip the word being typed, or the word just committed, to the other language. Flipping a committed word
    /// teaches its new reading and takes one count off its old one (a no-op when that was never learned), so a
    /// word flipped there and back, or learned in the other language on an earlier day, is not left learned in
    /// both. A word flipped while typing is taught when it is committed or its suggestion is picked.
    public mutating func flip() -> FieldEdit? {
        if isComposing {
            forced = language.other
            language = language.other
            return .mark(Self.render(keys, as: language))
        }
        guard let l = last else { return nil }
        let text = Self.render(l.keys, as: l.language.other)
        suggester.learned.unlearn(l.text, as: l.language)
        suggester.learned.learn(text, as: l.language.other)
        last = (l.keys, text, l.language.other, l.after)
        previous = l.language.other
        language = l.language.other
        // Counted together: in the field the word and what follows can join into one character (e + U+0301).
        return .replace(deleting: (l.text + l.after).count, inserting: text + l.after)
    }

    private func decide(complete: Bool) -> Language {
        if let detector {
            return detector.decide(keys, complete: complete, previous: previous, learned: suggester.learned)
        }
        // Valid Hangul commits as Korean; while typing it keeps the previous language to avoid flicker.
        guard Hangul.compose(keys).isValid else { return .english }
        return complete ? .korean : (previous ?? .korean)
    }

    public static func render(_ keys: [KeyEvent], as language: Language) -> String {
        language == .english ? Dubeolsik.latin(keys) : Hangul.compose(keys).text
    }
}

extension Language {
    public var other: Language { self == .korean ? .english : .korean }
}
