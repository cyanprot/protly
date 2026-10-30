// Whether the field still holds the word Protly is typing, so the next key may delete and retype its tail
// (typing-fixes 001). The keyboard calls `decide` from every key and host callback, and before any delete over the
// word. It keeps a model of the text before the cursor from its own writes, because a web view reports the
// context late (enter-clears-web.md C1) and a host may cut it at the front.
//
// Rules for a word being typed, in order:
// 1. Text is selected (a double-tap or long-press on the word): abandon, so the next key does not write the old
//    word over the selection (edit-menu-missing.md 1.3, H3).
// 2. The context after the cursor changed (a tap inside the word): abandon. Protly never writes after the cursor.
// 3. The context before the cursor ends with the model (start + the word as written): keep.
// 4. It shows a state Protly's own writes passed through (a context that lags): keep.
// 5. Within `ownEditWindow` of Protly's last write the model is trusted for anything else: keep.
// 6. Otherwise the host changed the field (a sent message cleared it, the cursor moved): abandon.
// `hasText` is not used: WebKit reports false right after each edit (enter-clears-web.md 2), and a cleared field
// already fails rule 3.
// With no word being typed only the committed word's flip is checked: `lastTail` must still end the context.

public struct FieldWatch: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case keep
        /// The field changed under the word: drop it without touching the field.
        case abandon
        /// The committed word can no longer be flipped.
        case forgetLast
    }

    /// What the proxy reports now.
    public struct Observed: Sendable, Equatable {
        public var before: String
        public var after: String
        public var selected: String
        /// Read and ignored on purpose (see the rules above); kept so the tests can show it.
        public var hasText: Bool

        public init(before: String, after: String = "", selected: String = "", hasText: Bool = true) {
            self.before = before
            self.after = after
            self.selected = selected
            self.hasText = hasText
        }
    }

    /// How long after Protly's own write a context that matches nothing is still trusted to lag (F1 note in
    /// edit-menu-missing.md: callbacks for a keyboard's own edits arrive 50-70 ms late).
    public static let ownEditWindow = 0.3
    /// The most of the text before the word kept in the model. Contexts are compared by their tails.
    public static let keptStart = 1000
    /// The most earlier states kept for a lagging context.
    public static let keptLead = 64

    /// The text before the word, as Protly's model expects it (it includes Protly's own inserts that a lagging
    /// context does not show yet).
    public private(set) var start: String
    /// States of the text before the cursor from before `start` that a lagging context may still show.
    public private(set) var lead: [String]
    /// The context after the cursor at the word's first key.
    public private(set) var after: String
    /// Every state of the text Protly wrote after `start`, oldest first: the word key by key, including the state
    /// between the deletes and the insert (ㄱ to 가 passes through ""), then what Protly typed after it (a commit
    /// difference, a space, a newline). The last is what the field holds now.
    public private(set) var history: [String]
    /// The time (seconds, any monotonic clock) of Protly's last write.
    public private(set) var lastOwnEdit: Double?
    /// false when Protly does not know what the field holds (a cursor move, an action, a field change): the next
    /// word starts at the context as reported.
    public private(set) var known: Bool

    public init(start: String = "", after: String = "", history: [String] = [""], lead: [String] = [],
                lastOwnEdit: Double? = nil, known: Bool = true) {
        self.start = start
        self.after = after
        self.history = history.isEmpty ? [""] : history
        self.lead = lead
        self.lastOwnEdit = lastOwnEdit
        self.known = known
    }

    /// The text before the cursor as Protly's writes left it.
    public var expected: String { start + (history.last ?? "") }

    public func decide(_ o: Observed, composing: Bool, lastTail: String?, now: Double) -> Decision {
        guard composing else {
            if let lastTail, !o.before.hasSuffix(lastTail) { return .forgetLast }
            return .keep
        }
        if !o.selected.isEmpty { return .abandon }
        if !Self.sameHead(o.after, after) { return .abandon }
        if Self.sameTail(o.before, expected) { return .keep }
        if states.contains(where: { Self.lags(o.before, $0) }) { return .keep }
        if let t = lastOwnEdit, now >= t, now - t < Self.ownEditWindow { return .keep }
        return .abandon
    }

    /// The word's first key, before anything is written. If the context shows the model, or a state Protly's own
    /// writes passed through, the word starts where the model says (the context may lag behind a space or a
    /// commit Protly just sent). Otherwise it starts at the context.
    public mutating func begin(_ o: Observed) {
        let model = expected
        let earlier = states
        var newStart = o.before
        var newLead: [String] = []
        if known, o.selected.isEmpty, Self.sameHead(o.after, after) {
            if Self.sameTail(o.before, model) {
                newStart = o.before.count >= model.count ? o.before : model
            } else if let i = earlier.lastIndex(where: { Self.lags(o.before, $0) }) {
                newStart = model
                newLead = Array(earlier[i..<(earlier.count - 1)])
            }
        }
        start = String(newStart.suffix(Self.keptStart))
        lead = Array(newLead.suffix(Self.keptLead))
        after = o.after
        history = [""]
        known = true
    }

    /// Protly deleted `deleting` Characters before the cursor, one call each, then inserted `inserting`. Every
    /// state is kept: a lagging context may show the field after any delete, before the insert.
    public mutating func wrote(deleting: Int, inserting: String, at now: Double) {
        guard deleting > 0 || !inserting.isEmpty else { return }
        lastOwnEdit = now
        guard known else { return }
        var text = history.last ?? ""
        for _ in 0..<max(deleting, 0) {
            if text.isEmpty {
                // The delete reaches the text before the word (a backspace over the space before it): the states
                // so far become lead, and the start moves back one Character.
                lead = Array(states.suffix(Self.keptLead))
                start = String(start.dropLast())
                history = [""]
            } else {
                text.removeLast()
                history.append(text)
            }
        }
        if !inserting.isEmpty {
            text += inserting
            history.append(text)
        }
    }

    /// Protly no longer knows what the field holds.
    public mutating func forget() {
        known = false
        lead = []
        history = [""]
    }

    /// Every state Protly's writes passed through since the context last showed the model, oldest first.
    private var states: [String] { lead + history.map { start + $0 } }

    /// The proxy cuts the context at the front: two contexts agree when the shorter ends the longer. An empty
    /// context agrees only with an empty one (a cleared field must not look like a short one).
    static func sameTail(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        return a.count >= b.count ? a.hasSuffix(b) : b.hasSuffix(a)
    }

    /// The after-context is cut at the far end: two agree when the shorter starts the longer, and an empty one
    /// agrees only with an empty one (the cursor moved into text, or to the end of it).
    static func sameHead(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        return a.count >= b.count ? a.hasPrefix(b) : b.hasPrefix(a)
    }

    /// A lagging context shows an earlier state. An empty context is never taken as lag outside the own-edit
    /// window: it is how a field looks after the host sent and cleared it.
    static func lags(_ context: String, _ state: String) -> Bool {
        !context.isEmpty && sameTail(context, state)
    }
}
