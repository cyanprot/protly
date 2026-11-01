// Each target language's own name, for the bar's label ("→ Русский"). The request keeps the English name
// (Languages.name(of:), TARGET: Russian). Kept out of Languages.swift: tests/ios-app.test.js reads every
// ("code", "name") pair in that file and compares them with the extension's LANG_NAMES.

extension Languages {
    /// The language's name in that language, capitalized as a label. nil for a code that is not listed.
    public static func endonym(of code: String) -> String? {
        endonyms[code]
    }

    static let endonyms: [String: String] = [
        "ko": "한국어", "en": "English", "ru": "Русский", "es": "Español", "ja": "日本語",
        "zh": "中文", "fr": "Français", "de": "Deutsch", "uk": "Українська", "pt": "Português",
        "ar": "العربية", "be": "Беларуская", "bn": "বাংলা", "bg": "Български", "yue": "粵語",
        "hr": "Hrvatski", "cs": "Čeština", "da": "Dansk", "nl": "Nederlands", "et": "Eesti",
        "fi": "Suomi", "ka": "ქართული", "el": "Ελληνικά", "he": "עברית", "hi": "हिन्दी",
        "hu": "Magyar", "id": "Bahasa Indonesia", "it": "Italiano", "kk": "Қазақ тілі", "lv": "Latviešu",
        "lt": "Lietuvių", "ms": "Bahasa Melayu", "mn": "Монгол", "no": "Norsk", "fa": "فارسی",
        "pl": "Polski", "pa": "ਪੰਜਾਬੀ", "ro": "Română", "sr": "Српски", "sk": "Slovenčina",
        "sv": "Svenska", "tl": "Tagalog", "th": "ไทย", "tr": "Türkçe", "ur": "اردو",
        "uz": "Oʻzbekcha", "vi": "Tiếng Việt",
    ]
}
