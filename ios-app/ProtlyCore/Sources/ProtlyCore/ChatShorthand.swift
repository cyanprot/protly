// Chat shorthand that is Korean although it breaks the one-syllable-at-a-time rules.

public enum ChatShorthand {
    /// Two-consonant abbreviations. Their keys also spell rare English strings ("rt" = ㄱㅅ, "gd" = ㅎㅇ),
    /// so the frequency rule alone gives them to English. Left out on purpose because the keys are
    /// real English: ㄱㄷ ("re"), ㅁㅊ ("aw").
    public static let abbreviations: Set<String> = [
        "ㄱㅅ", "ㅎㅇ", "ㅈㅅ", "ㄹㅇ", "ㅇㅋ", "ㅅㄱ", "ㅊㅋ", "ㅇㅈ", "ㅈㅂ", "ㅂㅇ", "ㄱㅊ", "ㅃㅇ",
    ]

    /// Everyday words missing from ko_50k (a subtitle list) whose keys spell an English list word: 걍 "rid",
    /// 걔 "rO", 꽤 "Rho", 얘 "dO", 쟤 "wO", 뜰 "Emf". Added to the Korean list at `missingWordCount`, so 걍 beats
    /// "rid" after a Korean word and at a message start, and "get rid of" stays English after an English word.
    public static let missingWords = ["걍", "걔", "꽤", "얘", "쟤", "뜰"]
    public static let missingWordCount = 400

    /// Jamo whose repeated runs glue onto words (laughing, crying): ㅋㅋ진짜, 아ㅋㅋ진짜 (composes 앜ㅋ진짜), ㅠㅠ나도.
    static let glueJamo: Set<Character> = ["ㅋ", "ㅎ", "ㅠ", "ㅜ"]

    /// A run of lone jamo allowed before or between syllables: an abbreviation, or two or more of one glue jamo.
    static func isGlueRun(_ run: String) -> Bool {
        if abbreviations.contains(run) { return true }
        guard run.count >= 2, let first = run.first, glueJamo.contains(first) else { return false }
        return run.allSatisfy { $0 == first }
    }
}
