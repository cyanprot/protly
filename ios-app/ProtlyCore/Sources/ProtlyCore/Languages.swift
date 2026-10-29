// The Chrome extension's target languages (src/lib/lang.js LANG_NAMES, same codes, names and order) and its
// draft prefix ("ru: 안녕" translates that draft into Russian). tests/ios-app.test.js fails when the list
// differs from LANG_NAMES; LanguagesTests repeats the cases of tests/lang.test.js for the prefix.

public enum Languages {
    /// ISO 639-1 codes (yue is 639-3), the extension's picker order.
    public static let names: [(code: String, name: String)] = [
        ("ko", "Korean"), ("en", "English"), ("ru", "Russian"), ("es", "Spanish"), ("ja", "Japanese"),
        ("zh", "Chinese"), ("fr", "French"), ("de", "German"), ("uk", "Ukrainian"), ("pt", "Portuguese"),
        ("ar", "Arabic"), ("be", "Belarusian"), ("bn", "Bengali"), ("bg", "Bulgarian"), ("yue", "Cantonese"),
        ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"), ("nl", "Dutch"), ("et", "Estonian"),
        ("fi", "Finnish"), ("ka", "Georgian"), ("el", "Greek"), ("he", "Hebrew"), ("hi", "Hindi"),
        ("hu", "Hungarian"), ("id", "Indonesian"), ("it", "Italian"), ("kk", "Kazakh"), ("lv", "Latvian"),
        ("lt", "Lithuanian"), ("ms", "Malay"), ("mn", "Mongolian"), ("no", "Norwegian"), ("fa", "Persian"),
        ("pl", "Polish"), ("pa", "Punjabi"), ("ro", "Romanian"), ("sr", "Serbian"), ("sk", "Slovak"),
        ("sv", "Swedish"), ("tl", "Tagalog"), ("th", "Thai"), ("tr", "Turkish"), ("ur", "Urdu"),
        ("uz", "Uzbek"), ("vi", "Vietnamese"),
    ]

    public static func name(of code: String) -> String? {
        names.first { $0.code == code }?.name
    }

    /// The prefix of a draft: spaces, 2-3 ASCII letters that are a listed code, a colon, spaces. The code comes back
    /// lowercased and the text without the prefix; anything else is (nil, the whole text). The rule of the
    /// extension's parseLangPrefix (`^\s*([a-z]{2,3}):\s*`, case-insensitive), with one difference: "ko" counts
    /// here, because on the keyboard it asks for a Korean polish.
    public static func prefix(of text: String) -> (code: String?, text: String) {
        let s = text.unicodeScalars
        var i = s.startIndex
        while i < s.endIndex, isSpace(s[i]) { i = s.index(after: i) }
        let start = i
        var letters = 0
        while i < s.endIndex, letters < 4, isLetter(s[i]) { i = s.index(after: i); letters += 1 }
        guard (2...3).contains(letters), i < s.endIndex, s[i] == ":" else { return (nil, text) }
        let code = String(s[start..<i]).lowercased()
        guard name(of: code) != nil else { return (nil, text) }
        i = s.index(after: i)
        while i < s.endIndex, isSpace(s[i]) { i = s.index(after: i) }
        return (code, String(s[i...]))
    }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c)
    }

    /// JavaScript's \s: its white space and line terminators. Not Foundation's set, which adds U+0085 and
    /// leaves out U+FEFF.
    private static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }
}
