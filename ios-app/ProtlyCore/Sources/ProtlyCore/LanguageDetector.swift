import Foundation

// Decides, per word, whether a key sequence is Korean or English.
// 1. Keys that do not compose into valid Hangul are English ("hello" starts with a lone vowel ㅗ).
// 2. Otherwise compare relative frequency in each language (count / list total, because the Korean
//    list is much smaller), plus `priorBonus` for the language of the previous word.
// 3. Unknown in English but valid Hangul: Korean (inflected Korean words are mostly not listed). On a
//    complete word unknown in both lists, a syllable followed by a trailing run of lone jamo that is not
//    glue (ChatShorthand.glueJamo) is English: a finished Korean word does not end in a stray consonant
//    (Spanish encanta = 둧뭇ㅁ, chaqueta = 촘볃ㅅㅁ).
// While typing (`complete == false`) a word with that key prefix stands in for the word.
// Words the user taught (LearnedWords) count as known in their language, with `learnedBonus` on top.

public enum Language: Sendable, Equatable {
    case korean, english
}

public struct LanguageDetector: Sendable {
    public let english: WordList
    public let korean: WordList
    public var priorBonus: Double

    /// A learned word scores at least this relative frequency (a fairly rare listed word), plus `learnedBonus`.
    /// Learned 걍 then beats "rid" after a Korean word and at a message start, not after an English word, and
    /// one flip can never take a common word (해 = "go") from its language.
    public static let learnedFloor = 1e-4
    public static let learnedBonus = 1.0

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

    public func decide(_ keys: [KeyEvent], complete: Bool, previous: Language?,
                       learned: LearnedWords = LearnedWords()) -> Language {
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
            // No English word fits: valid Hangul is Korean.
            if !english.hasPrefix(enKey), !learned.hasPrefix(enKey, in: .english) { return .korean }
            if !korean.hasPrefix(koKey), !learned.hasPrefix(koKey, in: .korean) { return .english }
            // Both languages still fit: keep the previous word's language (no flicker).
            // At the start of a message, Korean (the user's main language).
            return previous ?? .korean
        }
        let en = english.frequency(of: enKey)
        let ko = korean.frequency(of: koKey)
        let enLearned = learned.count(of: enKey, in: .english) > 0
        let koLearned = learned.count(of: koKey, in: .korean) > 0
        if en == 0, !enLearned {  // unknown English, valid Hangul
            if ko == 0, !koLearned, Self.endsInStrayConsonant(hangul.text) { return .english }
            return .korean
        }
        if ko == 0, !koLearned { return .english }
        var enScore = Self.score(en, english.total, learned: enLearned)
        var koScore = Self.score(ko, korean.total, learned: koLearned)
        if previous == .english { enScore += priorBonus }
        if previous == .korean { koScore += priorBonus }
        return koScore >= enScore ? .korean : .english
    }

    /// A syllable followed by a trailing run of lone jamo that is not glue (ㅋ ㅎ ㅠ ㅜ): 둧뭇ㅁ, 촘볃ㅅㅁ.
    /// False for 했ㅋㅋ and 앜ㅋ (glue), ㄱㅅ (no syllable) and 안녕 (no trailing jamo).
    static func endsInStrayConsonant(_ text: String) -> Bool {
        let tail = text.reversed().prefix(while: Hangul.isLoneJamo)
        guard !tail.isEmpty, tail.count < text.count else { return false }
        return !tail.allSatisfy { ChatShorthand.glueJamo.contains($0) }
    }

    /// Log relative frequency; a learned word gets the floor and the bonus (count 0 is -inf before the floor).
    static func score(_ count: Int, _ total: Double, learned: Bool) -> Double {
        let s = log(Double(count) / total)
        return learned ? max(s, log(learnedFloor)) + learnedBonus : s
    }

    /// The text the keys produce in a language.
    public func render(_ keys: [KeyEvent], as language: Language) -> String {
        TypingSession.render(keys, as: language)
    }
}
