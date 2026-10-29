// Raw key model and the Dubeolsik (2-set) key map.
// The keyboard records keys, not characters, so one key sequence can be read as English or Korean.

public enum Shift: Sendable, Equatable {
    case none
    case manual     // the user pressed shift or caps lock
    case automatic  // auto-capitalization turned shift on
}

public struct KeyEvent: Sendable, Equatable {
    public let letter: Character  // lowercase a-z for letter keys; anything else reads as non-Korean
    public let shift: Shift

    /// An uppercase letter (caps lock) is stored as its lowercase key with manual shift.
    public init(_ letter: Character, _ shift: Shift = .none) {
        if letter.isASCII, letter.isUppercase {
            self.letter = Character(letter.lowercased())
            self.shift = shift == .none ? .manual : shift
        } else {
            self.letter = letter
            self.shift = shift
        }
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
    /// sentence start must never turn ㅂ into ㅃ. nil for a key that is not a-z (digits, symbols).
    public static func jamo(for key: KeyEvent) -> Character? {
        if key.shift == .manual, let s = shifted[key.letter] { return s }
        return plain[key.letter]
    }

    /// The a-z key behind a keycap: an English letter (either case) or a Dubeolsik jamo (plain or shifted).
    /// nil for anything else (digits, symbols, accented callout letters).
    public static func letter(forKeycap cap: String) -> Character? {
        guard cap.count == 1, let c = cap.first else { return nil }
        if c.isASCII, c.isLetter { return Character(c.lowercased()) }
        return plain.first { $0.value == c }?.key ?? shifted.first { $0.value == c }?.key
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
