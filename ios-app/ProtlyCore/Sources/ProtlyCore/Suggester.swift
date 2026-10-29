// The suggestion for the bar's right slot while a word is typed: a fix (one English typo, a missing apostrophe,
// the user's text replacement) or a completion. Nothing here changes the field: a fix goes in only when the slot
// is tapped, never on space, return or punctuation. Learned words rank first in completions, the lists next.

public struct Suggester: Sendable {
    public var learned = LearnedWords()
    /// The system lexicon (text replacements, contact names): lowercased shortcut -> the text it stands for.
    /// An entry that is its own shortcut but for case (a contact "Will" comes as "will" -> "Will") marks a known
    /// word: no fix is offered for it.
    public var lexicon: [String: String] = [:]

    /// An unknown English word is offered a fix only to a list word at least this common (FrequencyWords counts
    /// out of 725 million, about 7 per million: the 6,300 most common words). At 1,000, subtitle junk took over
    /// chat slang: lmao -> "mao", wyd -> "syd", brb -> "barb".
    public static let minFixCount = 5_000

    /// Chat abbreviations one typo away from a common word (pls "plus", irl "girl", rly "fly", thx "th"): never
    /// offered a fix.
    static let slang: Set<String> = [
        "lol", "lmao", "lmfao", "rofl", "idk", "idc", "ikr", "ngl", "tbh", "smh", "imo", "imho", "hmu", "wyd", "wbu",
        "brb", "btw", "fyi", "irl", "pls", "plz", "thx", "omg", "omw", "nvm", "rly", "srsly", "abt", "cuz", "tho",
        "ofc", "ily", "asap", "lmk", "ttyl", "gtg", "wtf", "istg", "frfr",
    ]

    public init() {}

    /// Typed without the apostrophe; Apple suggests these too. Real words stay out (ill, well, were, its, id, hell).
    static let contractions: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've", "dont": "don't", "cant": "can't", "wont": "won't",
        "didnt": "didn't", "doesnt": "doesn't", "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't",
        "werent": "weren't", "couldnt": "couldn't", "wouldnt": "wouldn't", "shouldnt": "shouldn't",
        "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't", "thats": "that's", "whats": "what's",
        "youre": "you're", "theyre": "they're", "youve": "you've", "theyve": "they've", "weve": "we've",
    ]

    /// FrequencyWords splits "don't" into "don" + "'t": as a completion a stem shows the contraction, and a stem
    /// is never a fix.
    static let stems: Set<String> = [
        "don", "didn", "doesn", "isn", "wasn", "aren", "weren", "couldn", "wouldn", "shouldn", "haven", "hasn", "hadn",
    ]

    /// QWERTY neighbours (same row, row above, row below). A substitution only swaps neighbours.
    static let neighbours: [Character: String] = [
        "q": "wa", "w": "qeas", "e": "wrsd", "r": "etdf", "t": "ryfg", "y": "tugh", "u": "yihj", "i": "uojk",
        "o": "ipkl", "p": "ol", "a": "sqwz", "s": "adwezx", "d": "sferxc", "f": "dgrtcv", "g": "fhtyvb",
        "h": "gjyubn", "j": "hkuinm", "k": "jliom", "l": "kop", "z": "xas", "x": "zcsd", "c": "xvdf",
        "v": "cbfg", "b": "vngh", "n": "bmhj", "m": "njk",
    ]

    /// The fix the slot offers for the typed word, nil when none. Order: the lexicon (text replacements),
    /// then contractions, then one typo. Korean: text replacements only.
    public func fix(_ keys: [KeyEvent], as language: Language, lists: LanguageDetector?) -> String? {
        let typed = TypingSession.render(keys, as: language)
        let lower = typed.lowercased()
        // A shortcut is found in either reading, the current one first: after a Korean word the keys of "ty"
        // compose as 쇼.
        for reading in [lower, TypingSession.render(keys, as: language.other).lowercased()] {
            if let r = lexicon[reading] { return r.lowercased() == reading ? nil : r }
        }
        guard language == .english else { return nil }
        if let c = Self.contractions[lower] {
            let fixed = Self.matchCase(typed, c)
            return fixed == typed ? nil : fixed
        }
        guard let english = lists?.english, lower.count >= 3, !Self.slang.contains(lower),
              english.frequency(of: lower) == 0, learned.count(of: lower, in: .english) == 0 else { return nil }
        // A common longer word starts with the typed letters: the word is still being typed (abo -> "about"),
        // not a typo of "ago". Without this, 700 of the 2,076 en_50k top-3,000 words of 5+ letters showed a wrong
        // fix on the way (othe -> "the", thos -> "this", gre -> "grew").
        if let c = english.completion(of: lower), english.frequency(of: c) >= Self.minFixCount { return nil }
        // Two-letter targets are mostly subtitle fragments (th, sh, hm): never a fix.
        let best = Self.edits(lower).filter { $0.count >= 3 && !Self.stems.contains($0) }
            .max { (english.frequency(of: $0), $1) < (english.frequency(of: $1), $0) }
        guard let best, english.frequency(of: best) >= Self.minFixCount else { return nil }
        return Self.matchCase(typed, best)
    }

    /// A longer word for the keys typed so far, nil when none.
    public func completion(_ keys: [KeyEvent], as language: Language, lists: LanguageDetector?) -> String? {
        guard !keys.isEmpty else { return nil }
        switch language {
        case .english:
            let typed = Dubeolsik.latin(keys)
            let prefix = typed.lowercased()
            if let w = learned.completion(of: prefix, in: .english) { return Self.matchCase(typed, w) }
            return lists?.english.completion(of: prefix).map { Self.matchCase(typed, Self.stems.contains($0) ? $0 + "'t" : $0) }
        case .korean:
            let key = Dubeolsik.koreanKeyString(keys)
            if let w = learned.completion(of: key, in: .korean) { return w }
            return lists?.korean.completion(of: key).map { Hangul.compose($0.map { KeyEvent($0) }).text }
        }
    }

    /// Words one typo away: a key missed, an extra key, a neighbour key, two keys swapped.
    static func edits(_ word: String) -> Set<String> {
        let c = Array(word)
        var out: Set<String> = []
        for i in c.indices {
            var d = c
            d.remove(at: i)
            out.insert(String(d))
            for n in neighbours[c[i]] ?? "" {
                var s = c
                s[i] = n
                out.insert(String(s))
            }
            if i + 1 < c.count {
                var t = c
                t.swapAt(i, i + 1)
                out.insert(String(t))
            }
        }
        for i in 0...c.count {
            for l in "abcdefghijklmnopqrstuvwxyz" {
                var s = c
                s.insert(l, at: i)
                out.insert(String(s))
            }
        }
        out.remove(word)
        return out
    }

    /// The typed word's case on a suggestion: all caps stays all caps, a capital first letter stays.
    static func matchCase(_ typed: String, _ word: String) -> String {
        if typed.count >= 2, typed.allSatisfy(\.isUppercase) { return word.uppercased() }
        if typed.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }
}
