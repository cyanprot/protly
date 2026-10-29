// Dubeolsik composition: jamo sequence -> Hangul syllables. libhangul's 2-set rules:
// compound vowels and finals, and a final consonant moves to the next syllable when a vowel follows.
// Backspace is "drop the last key and recompose", which gives Apple's jamo-by-jamo delete.

public struct Composition: Sendable, Equatable {
    public let text: String
    /// True when every lone jamo sits in one run at the end ("좋아ㅋㅋ", "ㅇㅇ", or a lead consonant
    /// still waiting for its vowel) and that run's lone vowels are chat faces (ㅠ ㅜ ㅡ).
    /// A lone jamo before a syllable means the keys were not Korean.
    public let isValid: Bool
}

public enum Hangul {
    static let choseong: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let jungseong: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let jongseong: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")  // index + 1
    static let vowelPairs: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    static let finalPairs: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
        "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]

    static func isVowel(_ c: Character) -> Bool { jungseong.contains(c) }

    /// Compatibility jamo block U+3131...U+318E (a lone jamo in text).
    static func isLoneJamo(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x3131...0x318E).contains(v)
    }

    static func isSyllable(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0xAC00...0xD7A3).contains(v)
    }

    public static func compose(_ keys: [KeyEvent]) -> Composition {
        // A key with no jamo (not a-z) passes through as itself and makes the word invalid Hangul.
        compose(jamos: keys.map { Dubeolsik.jamo(for: $0) ?? $0.letter })
    }

    /// Anything that is not a key-typable lead consonant or vowel (ㄳ, "a") is appended as-is
    /// and makes the result invalid.
    static func compose(jamos: [Character]) -> Composition {
        var c = Composer()
        for j in jamos { c.feed(j) }
        let text = c.finish()
        // Valid when, after dropping the trailing run of lone jamo, no lone jamo is left.
        let tail = text.reversed().prefix(while: isLoneJamo)
        let head = text.reversed().drop(while: isLoneJamo)
        let faceVowels: Set<Character> = ["ㅠ", "ㅜ", "ㅡ"]
        let tailOK = tail.allSatisfy { !isVowel($0) || faceVowels.contains($0) }
        let typable = jamos.allSatisfy { choseong.contains($0) || isVowel($0) }
        return Composition(text: text, isValid: typable && tailOK && !head.contains(where: isLoneJamo))
    }
}

private struct Composer {
    var cho: Character?
    var jung: Character?
    var jong: [Character] = []
    var out = ""

    mutating func feed(_ j: Character) {
        Hangul.isVowel(j) ? feedVowel(j) : feedConsonant(j)
    }

    mutating func feedConsonant(_ c: Character) {
        if cho != nil, jung != nil {
            if jong.isEmpty, Hangul.jongseong.contains(c) { jong = [c]; return }
            if jong.count == 1, Hangul.finalPairs[String([jong[0], c])] != nil { jong.append(c); return }
        }
        flush()
        guard Hangul.choseong.contains(c) else { out.append(c); return }  // cannot lead a syllable
        cho = c
    }

    mutating func feedVowel(_ v: Character) {
        if cho != nil, jung == nil { jung = v; return }
        if let cur = jung, jong.isEmpty, let pair = Hangul.vowelPairs[String([cur, v])] { jung = pair; return }
        if cho != nil, jung != nil, !jong.isEmpty {
            let moved = jong.removeLast()
            flush()
            cho = moved
            jung = v
            return
        }
        flush()
        jung = v
    }

    mutating func flush() {
        defer { cho = nil; jung = nil; jong = [] }
        switch (cho, jung) {
        case let (l?, v?):
            let li = Hangul.choseong.firstIndex(of: l)!
            let vi = Hangul.jungseong.firstIndex(of: v)!
            var ti = 0
            if !jong.isEmpty {
                let t = jong.count == 2 ? Hangul.finalPairs[String(jong)]! : jong[0]
                ti = Hangul.jongseong.firstIndex(of: t)! + 1
            }
            out.append(Character(Unicode.Scalar(UInt32(0xAC00 + (li * 21 + vi) * 28 + ti))!))
        case let (l?, nil): out.append(l)
        case let (nil, v?): out.append(v)
        case (nil, nil): break
        }
    }

    mutating func finish() -> String {
        flush()
        return out
    }
}
