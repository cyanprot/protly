import XCTest
@testable import ProtlyCore

// The cases of tests/lang.test.js (parseLangPrefix), plus the one keyboard difference: "ko:" is a prefix here.
final class LanguagesTests: XCTestCase {
    private func parse(_ s: String) -> [String?] {
        let p = Languages.prefix(of: s)
        return [p.code, p.text]
    }

    func testTheListIsTheExtensionsList() {
        XCTAssertEqual(Languages.names.count, 47)  // tests/ios-app.test.js compares every entry with LANG_NAMES
        XCTAssertEqual(Languages.name(of: "ru"), "Russian")
        XCTAssertEqual(Languages.name(of: "yue"), "Cantonese")
        XCTAssertNil(Languages.name(of: "xx"))
    }

    func testAKnownCodePicksTheLanguageAndIsDropped() {
        XCTAssertEqual(parse("ru: 안녕"), ["ru", "안녕"])
        XCTAssertEqual(parse("ja: 첫줄\n둘째 줄"), ["ja", "첫줄\n둘째 줄"])
        XCTAssertEqual(parse("  RU:안녕"), ["ru", "안녕"])
        XCTAssertEqual(parse("ru:\n\n안녕"), ["ru", "안녕"])
        XCTAssertEqual(parse("\u{FEFF}\u{3000}es: 안녕"), ["es", "안녕"])  // JavaScript's \s has both
    }

    func testUnknownCodesALatePrefixAndURLsStayText() {
        for s in ["ok: 안녕", "안녕 ru:", "https://x.com 안녕", "xx: 안녕", "rus: 안녕", "r: 안녕", "ru 안녕", "겨: 안녕",
                  "\u{85}ru: 안녕", ""] {
            XCTAssertEqual(parse(s), [nil, s], s)
        }
    }

    func testKoIsAPrefixOnTheKeyboardOnly() {
        // parseLangPrefix refuses ko. On the keyboard "ko:" asks for a Korean polish (ActionAPI.mode).
        XCTAssertEqual(parse("ko: 안녕"), ["ko", "안녕"])
    }
}
