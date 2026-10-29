// Chat shorthand that is Korean although it breaks the one-syllable-at-a-time rules.

public enum ChatShorthand {
    /// Two-consonant abbreviations. Their keys also spell rare English strings ("rt" = ㄱㅅ, "gd" = ㅎㅇ),
    /// so the frequency rule alone gives them to English. Left out on purpose because the keys are
    /// real English: ㄱㄷ ("re"), ㅁㅊ ("aw").
    public static let abbreviations: Set<String> = [
        "ㄱㅅ", "ㅎㅇ", "ㅈㅅ", "ㄹㅇ", "ㅇㅋ", "ㅅㄱ", "ㅊㅋ", "ㅇㅈ", "ㅈㅂ", "ㅂㅇ", "ㄱㅊ", "ㅃㅇ",
    ]

    /// Jamo whose repeated runs glue onto words (laughing, crying): ㅋㅋ진짜, 아ㅋㅋ진짜 (composes 앜ㅋ진짜), ㅠㅠ나도.
    static let glueJamo: Set<Character> = ["ㅋ", "ㅎ", "ㅠ", "ㅜ"]

    /// A run of lone jamo allowed before or between syllables: an abbreviation, or two or more of one glue jamo.
    static func isGlueRun(_ run: String) -> Bool {
        if abbreviations.contains(run) { return true }
        guard run.count >= 2, let first = run.first, glueJamo.contains(first) else { return false }
        return run.allSatisfy { $0 == first }
    }
}
