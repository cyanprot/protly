// Words the user taught protly by flipping a word to the other language. Keyed like the word lists (English:
// lowercase; Korean: key string), so the detector and the completions read them the same way. Saved by the
// keyboard in its own container as JSON.

public struct LearnedWords: Sendable, Equatable, Codable {
    struct Entry: Sendable, Equatable, Codable {
        var text: String
        var count: Int
    }

    private var english: [String: Entry] = [:]
    private var korean: [String: Entry] = [:]
    /// Bumped on every change, not saved: the keyboard saves when it moved.
    public private(set) var changes = 0
    /// Per language. A new word past the limit pushes out the least used one.
    public static let limit = 1000
    /// Longer keys are not learned. Typed text is saved, so the store stays small: at most
    /// 2 x 1,000 x 32 key characters.
    public static let maxKeyLength = 32

    private enum CodingKeys: String, CodingKey { case english, korean }

    public init() {}

    /// The list key of a word, nil when it cannot be typed as one word (English: a-z only; Korean: Hangul only)
    /// or its key is longer than `maxKeyLength`.
    public static func key(of text: String, in language: Language) -> String? {
        guard !text.isEmpty, text.count <= maxKeyLength else { return nil }  // a key is never shorter than its text
        let key: String?
        switch language {
        case .english:
            let lower = text.lowercased()
            key = lower.allSatisfy { $0.isASCII && $0.isLetter } ? lower : nil
        case .korean:
            key = KeyEncoder.keys(forHangul: text).map(Dubeolsik.koreanKeyString)
        }
        return key.flatMap { $0.count <= maxKeyLength ? $0 : nil }
    }

    public mutating func learn(_ text: String, as language: Language) {
        guard let key = Self.key(of: text, in: language) else { return }
        edit(language) { words in
            if words[key] == nil, words.count >= Self.limit,
               let least = words.min(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) })?.key {
                words[least] = nil
            }
            words[key] = Entry(text: text, count: (words[key]?.count ?? 0) + 1)
        }
    }

    /// Takes back one `learn` (a committed word flipped again). The word goes when its count reaches 0.
    public mutating func unlearn(_ text: String, as language: Language) {
        guard let key = Self.key(of: text, in: language), let entry = words(language)[key] else { return }
        edit(language) { words in
            words[key] = entry.count > 1 ? Entry(text: entry.text, count: entry.count - 1) : nil
        }
    }

    public func count(of key: String, in language: Language) -> Int {
        words(language)[key]?.count ?? 0
    }

    public func hasPrefix(_ prefix: String, in language: Language) -> Bool {
        words(language).keys.contains { $0.hasPrefix(prefix) }
    }

    /// The most used learned word whose key starts with `prefix` and is longer: its text as taught.
    public func completion(of prefix: String, in language: Language) -> String? {
        words(language)
            .filter { $0.key.count > prefix.count && $0.key.hasPrefix(prefix) }
            .max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?
            .value.text
    }

    /// Number of learned words in a language (tests check the limits with it).
    func size(_ language: Language) -> Int { words(language).count }

    private func words(_ language: Language) -> [String: Entry] {
        language == .english ? english : korean
    }

    private mutating func edit(_ language: Language, _ change: (inout [String: Entry]) -> Void) {
        if language == .english { change(&english) } else { change(&korean) }
        changes += 1
    }
}
