import Foundation

// Decides, per word, whether a key sequence is Korean or English.
// 1. Keys that do not compose into valid Hangul are English ("hello" starts with a lone vowel ㅗ).
// 2. Otherwise compare relative frequency in each language (count / list total, because the Korean
//    list is much smaller), plus `priorBonus` for the language of the previous word.
// 3. Unknown in both lists but valid Hangul: Korean (inflected Korean words are mostly not listed).
// While typing (`complete == false`) a word with that key prefix stands in for the word.

public enum Language: Sendable, Equatable {
    case korean, english
}

public struct LanguageDetector: Sendable {
    public let english: WordList
    public let korean: WordList
    public var priorBonus: Double

    public init(english: WordList, korean: WordList, priorBonus: Double = 2.0) {
        self.english = english
        self.korean = korean
        self.priorBonus = priorBonus
    }

    public static func bundled(priorBonus: Double = 2.0) throws -> LanguageDetector {
        LanguageDetector(
            english: .english(try WordList.bundled("en_50k")),
            korean: .korean(try WordList.bundled("ko_50k"),
                            adding: ChatShorthand.missingWords.map { ($0, ChatShorthand.missingWordCount) }),
            priorBonus: priorBonus
        )
    }

    public func decide(_ keys: [KeyEvent], complete: Bool, previous: Language?) -> Language {
        let hangul = Hangul.compose(keys)
        guard hangul.isValid else { return .english }
        // Two-consonant chat abbreviations (ㄱㅅ, ㅎㅇ): their keys spell rare English strings. Only on a
        // complete word: while typing, "tr" (ㅅㄱ) would flip true/try/trip to Korean at the second key.
        if complete, ChatShorthand.abbreviations.contains(hangul.text) { return .korean }
        // Chat shorthand: one jamo repeated (ㅋㅋ ㅇㅇ ㄱㄱ ㅠㅠ). "dd", "gg" also occur in English subtitles.
        if hangul.text.count >= 2, Set(hangul.text).count == 1, Hangul.isLoneJamo(hangul.text.first!) {
            return .korean
        }
        // Shift inside a word on a key with a doubled jamo (rO = 걔, dO = 얘, goT = 했) is Korean: English does not
        // capitalize mid-word in a word that also composes as Hangul. Every key shifted is caps lock, not Korean.
        if keys.dropFirst().contains(where: { $0.shift == .manual && Dubeolsik.shifted[$0.letter] != nil }),
           keys.contains(where: { $0.shift == .none }) {
            return .korean
        }
        let enKey = Dubeolsik.latin(keys).lowercased()
        let koKey = Dubeolsik.koreanKeyString(keys)
        if !complete {
            // While typing only "does any word start with these keys" matters.
            if !english.hasPrefix(enKey) { return .korean }  // no English word fits, valid Hangul
            if !korean.hasPrefix(koKey) { return .english }
            // Both languages still fit: keep the previous word's language (no flicker).
            // At the start of a message, Korean (the user's main language).
            return previous ?? .korean
        }
        let en = english.frequency(of: enKey)
        let ko = korean.frequency(of: koKey)
        if en == 0 { return .korean }  // unknown English, valid Hangul
        if ko == 0 { return .english }
        var enScore = log(Double(en) / english.total)
        var koScore = log(Double(ko) / korean.total)
        if previous == .english { enScore += priorBonus }
        if previous == .korean { koScore += priorBonus }
        return koScore >= enScore ? .korean : .english
    }

    /// The text the keys produce in a language.
    public func render(_ keys: [KeyEvent], as language: Language) -> String {
        TypingSession.render(keys, as: language)
    }
}
