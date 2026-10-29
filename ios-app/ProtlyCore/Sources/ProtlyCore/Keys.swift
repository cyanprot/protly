// Raw key model and the Dubeolsik (2-set) key map.
// The keyboard records keys, not characters, so one key sequence can be read as English or Korean.

public enum Shift: Sendable, Equatable {
    case none
    case manual     // the user pressed shift or caps lock
    case automatic  // auto-capitalization turned shift on
}

public struct KeyEvent: Sendable, Equatable {
    public let letter: Character  // always lowercase a-z
    public let shift: Shift

    public init(_ letter: Character, _ shift: Shift = .none) {
        self.letter = letter
        self.shift = shift
    }
}

public enum Dubeolsik {
    static let plain: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
    ]
    static let shifted: [Character: Character] = [
        "q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ", "o": "ㅒ", "p": "ㅖ",
    ]

    /// Korean jamo for a key. Only MANUAL shift selects the shifted jamo: an auto-capitalized
    /// sentence start must never turn ㅂ into ㅃ.
    public static func jamo(for key: KeyEvent) -> Character {
        if key.shift == .manual, let s = shifted[key.letter] { return s }
        return plain[key.letter]!
    }

    /// Key string of the Korean reading: lowercase letters, uppercase only where the shifted jamo is used.
    /// This is the lookup key of the Korean word list.
    public static func koreanKeyString(_ keys: [KeyEvent]) -> String {
        String(keys.map { k in
            (k.shift == .manual && shifted[k.letter] != nil) ? Character(k.letter.uppercased()) : k.letter
        })
    }

    /// English reading: any shift capitalizes.
    public static func latin(_ keys: [KeyEvent]) -> String {
        String(keys.map { $0.shift == .none ? $0.letter : Character($0.letter.uppercased()) })
    }
}
