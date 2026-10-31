// Whether the field still holds the word Protly is typing, so the next key may delete and retype its tail
// (typing-fixes 001). The keyboard calls `decide` from every key and host callback, and before any write over the
// word. It keeps a model of the text before the cursor from its own writes, because a web view reports the
// context late (enter-clears-web.md C1) and a host may cut it at the front.
//
// Rules for a word being typed, in order:
// 1. Text is selected (a double-tap or long-press on the word): abandon, so the next key does not write the old
//    word over the selection (edit-menu-missing.md 1.3, H3).
// 2. The context after the cursor changed (a tap inside the word): abandon. Protly never writes after the cursor.
// 3. The context before the cursor ends with the model (start + the word as written): keep.
// 4. It shows an earlier state of Protly's writes: keep while Protly wrote past that state less than `lagWindow`
//    ago (a context that lags), abandon after that. A field that silently drops an insert (a length cap, an input
//    filter) or a host undo also shows an earlier state; keeping the word there would let the next key delete the
//    user's text. A split word is fine, deleting user text is not.
// 5. A context that matches nothing, within `ownEditWindow` of Protly's last write (an empty read from a web view
//    that is catching up): keep.
// 6. Otherwise the host changed the field (a sent message cleared it, the cursor moved): abandon.
// `hasText` is not used: WebKit reports false right after each edit (enter-clears-web.md 2), and a cleared field
// already fails rule 3. A no-break space (U+00A0) counts as a space: WebKit reports a trailing space that way in
// contenteditable fields.
// With no word being typed only the committed word's flip is checked: `lastTail` must still end the context, and
// no text may be selected (the flip deletes before the cursor, which would take the selection with it).

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

    /// How long after Protly's own write a context that matches nothing is still trusted (F1 note in
    /// edit-menu-missing.md: callbacks for a keyboard's own edits arrive 50-70 ms late).
    public static let ownEditWindow = 0.3
    /// How long after Protly wrote past a state a context may still show it: twice the measured 50-70 ms lag.
    public static let lagWindow = 0.15
    /// The most of the text before the word kept in the model. Contexts are compared by their tails.
    public static let keptStart = 1000
    /// The most earlier states kept, before the start (`lead`) and after it (`history`).
    public static let keptLead = 64
    public static let keptHistory = 64

    /// The text before the word, as Protly's model expects it (it includes Protly's own inserts that a lagging
    /// context does not show yet).
    public private(set) var start: String
    /// States of the text before the cursor from before `start` that a lagging context may still show.
    public private(set) var lead: [String]
    /// The context after the cursor at the word's first key.
    public private(set) var after: String
    /// Every state of the text Protly wrote after `start`, oldest first: the word key by key, including the states
    /// between the deletes and the insert (ㄱ to 가 passes through ""), then what Protly typed after it (a commit
    /// difference, a space, a newline). The last is what the field holds now.
    public private(set) var history: [String]
    /// The time of Protly's last write (seconds, any monotonic clock).
    public private(set) var lastOwnEdit: Double?
    /// false when Protly does not know what the field holds (a cursor move, an action, a field change): the next
    /// word starts at the context as reported.
    public private(set) var known: Bool
    /// When Protly wrote each state of `lead` and `history` (nil: not written by Protly, or unknown).
    private var leadAt: [Double?]
    private var historyAt: [Double?]

    /// A model with `history` written at `lastOwnEdit` (the first state, the start, at no known time).
    public init(start: String = "", after: String = "", history: [String] = [""], lead: [String] = [],
                lastOwnEdit: Double? = nil, known: Bool = true) {
        let states = history.isEmpty ? [""] : history
        self.start = start
        self.after = after
        self.history = states
        self.lead = lead
        self.lastOwnEdit = lastOwnEdit
        self.known = known
        leadAt = lead.map { _ in lastOwnEdit }
        historyAt = [nil] + Array(repeating: lastOwnEdit, count: states.count - 1)
    }

    /// The text before the cursor as Protly's writes left it.
    public var expected: String { start + (history.last ?? "") }

    public func decide(_ o: Observed, composing: Bool, lastTail: String?, now: Double) -> Decision {
        guard composing else {
            guard let lastTail else { return .keep }
            return o.selected.isEmpty && o.before.hasSuffix(lastTail) ? .keep : .forgetLast
        }
        if !o.selected.isEmpty { return .abandon }
        if !Self.sameHead(o.after, after) { return .abandon }
        if Self.sameTail(o.before, expected) { return .keep }
        if let i = newestEarlierState(o) { return isLagging(i, now: now) ? .keep : .abandon }
        if let t = lastOwnEdit, now >= t, now - t < Self.ownEditWindow { return .keep }
        return .abandon
    }

    /// The word's first key, before anything is written. If the context shows the model, or a state Protly wrote
    /// past less than `lagWindow` ago, the word starts where the model says (the context may lag behind a space
    /// or a commit Protly just sent). Otherwise it starts at the context.
    public mutating func begin(_ o: Observed, now: Double) {
        let model = expected
        let earlier = states
        let earlierAt = times
        var newStart = o.before
        var newLead: [String] = []
        var newLeadAt: [Double?] = []
        var startAt: Double? = nil
        if known, o.selected.isEmpty, Self.sameHead(o.after, after) {
            if Self.sameTail(o.before, model) {
                newStart = o.before.count >= model.count ? o.before : model
                startAt = earlierAt.last ?? nil
            } else if let i = newestEarlierState(o), isLagging(i, now: now) {
                newStart = model
                newLead = Array(earlier[i..<(earlier.count - 1)])
                newLeadAt = Array(earlierAt[i..<(earlierAt.count - 1)])
                startAt = earlierAt.last ?? nil
            }
        }
        start = String(newStart.suffix(Self.keptStart))
        lead = Array(newLead.suffix(Self.keptLead))
        leadAt = Array(newLeadAt.suffix(Self.keptLead))
        after = o.after
        history = [""]
        historyAt = [startAt]
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
                leadAt = Array(times.suffix(Self.keptLead))
                start = String(start.dropLast())
                history = [""]
                historyAt = [now]
            } else {
                text.removeLast()
                history.append(text)
                historyAt.append(now)
            }
        }
        if !inserting.isEmpty {
            text += inserting
            history.append(text)
            historyAt.append(now)
        }
        if history.count > Self.keptHistory {
            // A long run of Protly's writes with no new word (digits, punctuation, backspaces): the oldest states
            // move to lead, which keeps the newest.
            let n = history.count - Self.keptHistory
            lead = Array((lead + history.prefix(n).map { start + $0 }).suffix(Self.keptLead))
            leadAt = Array((leadAt + historyAt.prefix(n)).suffix(Self.keptLead))
            history.removeFirst(n)
            historyAt.removeFirst(n)
        }
    }

    /// Protly no longer knows what the field holds.
    public mutating func forget() {
        known = false
        lead = []
        leadAt = []
        history = [""]
        historyAt = [nil]
    }

    /// Every state Protly's writes passed through since the context last showed the model, oldest first, and
    /// when each was written.
    private var states: [String] { lead + history.map { start + $0 } }
    private var times: [Double?] { leadAt + historyAt }

    /// The index in `states` of the newest earlier state the context shows (not the last: that is rule 3).
    private func newestEarlierState(_ o: Observed) -> Int? {
        let s = states
        return s.indices.dropLast().last { Self.lags(o.before, s[$0]) }
    }

    /// Protly wrote past state `i` (wrote state `i + 1`) less than `lagWindow` ago.
    private func isLagging(_ i: Int, now: Double) -> Bool {
        let t = times
        guard i + 1 < t.count, let next = t[i + 1] else { return false }
        return now >= next && now - next < Self.lagWindow
    }

    /// The proxy cuts the context at the front: two contexts agree when the shorter ends the longer. An empty
    /// context agrees only with an empty one (a cleared field must not look like a short one).
    static func sameTail(_ a: String, _ b: String) -> Bool {
        let a = plain(a), b = plain(b)
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        return a.count >= b.count ? a.hasSuffix(b) : b.hasSuffix(a)
    }

    /// The after-context is cut at the far end: two agree when the shorter starts the longer, and an empty one
    /// agrees only with an empty one (the cursor moved into text, or to the end of it).
    static func sameHead(_ a: String, _ b: String) -> Bool {
        let a = plain(a), b = plain(b)
        if a.isEmpty || b.isEmpty { return a.isEmpty && b.isEmpty }
        return a.count >= b.count ? a.hasPrefix(b) : b.hasPrefix(a)
    }

    /// U+00A0 read as a space: WebKit stores a space typed at the end of a contenteditable field as one.
    static func plain(_ s: String) -> String {
        s.contains("\u{00A0}") ? String(s.map { $0 == "\u{00A0}" ? " " : $0 }) : s
    }

    /// A lagging context shows an earlier state. An empty context is never taken as lag: it is how a field looks
    /// after the host sent and cleared it.
    static func lags(_ context: String, _ state: String) -> Bool {
        !context.isEmpty && sameTail(context, state)
    }
}
