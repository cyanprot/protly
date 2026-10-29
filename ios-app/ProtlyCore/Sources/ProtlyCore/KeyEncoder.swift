// Text -> key events: the inverse of the keyboard. Used to load the Korean word list (keyed by keys)
// and to turn the evaluation corpus into the keys a user would press.

public enum KeyEncoder {
    private static let keyForJamo: [Character: KeyEvent] = {
        var m: [Character: KeyEvent] = [:]
        for (k, j) in Dubeolsik.plain { m[j] = KeyEvent(k) }
        for (k, j) in Dubeolsik.shifted { m[j] = KeyEvent(k, .manual) }
        return m
    }()
    private static let splitVowel = Dictionary(uniqueKeysWithValues: Hangul.vowelPairs.map { ($0.value, Array($0.key)) })
    private static let splitFinal = Dictionary(uniqueKeysWithValues: Hangul.finalPairs.map { ($0.value, Array($0.key)) })

    /// Keys for a word made only of Hangul syllables and lone jamo. nil for anything else.
    public static func keys(forHangul word: String) -> [KeyEvent]? {
        var jamos: [Character] = []
        for ch in word {
            if Hangul.isSyllable(ch) {
                let s = Int(ch.unicodeScalars.first!.value) - 0xAC00
                let l = s / 588, v = (s % 588) / 28, t = s % 28
                jamos.append(Hangul.choseong[l])
                let vowel = Hangul.jungseong[v]
                jamos += splitVowel[vowel] ?? [vowel]
                if t > 0 {
                    let fin = Hangul.jongseong[t - 1]
                    jamos += splitFinal[fin] ?? [fin]
                }
            } else if Hangul.isLoneJamo(ch) {
                jamos += splitVowel[ch] ?? splitFinal[ch] ?? [ch]
            } else {
                return nil
            }
        }
        var keys: [KeyEvent] = []
        for j in jamos {
            guard let k = keyForJamo[j] else { return nil }
            keys.append(k)
        }
        return keys
    }

    /// Keys for an ASCII-letter word. Capitals are manual shift, except the first letter of a
    /// sentence, which auto-capitalization typed (`sentenceStart`).
    public static func keys(forLatin word: String, sentenceStart: Bool) -> [KeyEvent]? {
        var keys: [KeyEvent] = []
        for (i, ch) in word.enumerated() {
            guard ch.isASCII, ch.isLetter else { return nil }
            let lower = Character(ch.lowercased())
            if ch.isUppercase {
                keys.append(KeyEvent(lower, (i == 0 && sentenceStart) ? .automatic : .manual))
            } else {
                keys.append(KeyEvent(lower))
            }
        }
        return keys
    }
}
