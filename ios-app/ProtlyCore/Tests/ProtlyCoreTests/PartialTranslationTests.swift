import Foundation
import XCTest
@testable import ProtlyCore

final class PartialTranslationTests: XCTestCase {
    private func value(_ text: String) -> String? { PartialTranslation.value(in: text) }

    /// Fed one Unicode scalar at a time, the value only grows, and ends where the whole text does.
    private func assertAnySplitAgrees(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        var p = PartialTranslation()
        var last: String?
        for s in text.unicodeScalars {
            let before = p.value
            let changed = p.append(String(s))
            XCTAssertEqual(changed, p.value != before, "changed flag at \(s)", file: file, line: line)
            if let v = p.value, let l = last {
                XCTAssertTrue(v.hasPrefix(l), "\(v) does not extend \(l)", file: file, line: line)
            }
            last = p.value
        }
        XCTAssertEqual(p.value, value(text), file: file, line: line)
    }

    func testNilBeforeTheValueStarts() {
        for text in ["", "{", #"{"transl"#, #"{"translation""#, #"{"translation":"#, #"{"translation": "#,
                     #"{"back_translation": "Hi""#] {
            XCTAssertNil(value(text), text)
        }
        XCTAssertEqual(value(#"{"translation": ""#), "")
    }

    func testTheValueSoFar() {
        XCTAssertEqual(value(#"{"translation": "Thanks for"#), "Thanks for")
        XCTAssertEqual(value(#"{"translation": "Thanks for today", "back_translation": "오늘"#), "Thanks for today")
    }

    func testEveryEscape() {
        XCTAssertEqual(value(#"{"translation": "q\" b\\ s\/ \b\f\n\r\t end"#), "q\" b\\ s/ \u{8}\u{C}\n\r\t end")
        XCTAssertEqual(value(#"{"translation": "\u00e9\u0041\uAC00""#), "éA가")
    }

    func testAUnicodeEscapeCutAcrossDeltasIsHeldBack() {
        for cut in [#"\"#, #"\u"#, #"\u0"#, #"\u00"#, #"\u00e"#] {
            XCTAssertEqual(value(#"{"translation": "a"# + cut), "a", cut)
        }
        var p = PartialTranslation()
        p.append(#"{"translation": "a\u00"#)
        XCTAssertEqual(p.value, "a")
        p.append("e9")
        XCTAssertEqual(p.value, "aé")
    }

    func testSurrogatePairs() {
        XCTAssertEqual(value(#"{"translation": "x\ud83d\ude00y"#), "x😀y")
        // The high half waits for the low half.
        XCTAssertEqual(value(#"{"translation": "x\ud83d"#), "x")
        XCTAssertEqual(value(#"{"translation": "x\ud83d\ude0"#), "x")
        // A lone half is a replacement character, never a broken string.
        XCTAssertEqual(value(#"{"translation": "x\ud83dy"#), "x\u{FFFD}y")
        XCTAssertEqual(value(#"{"translation": "x\ude00y"#), "x\u{FFFD}y")
        XCTAssertEqual(value(#"{"translation": "x\ud83d""#), "x\u{FFFD}")
    }

    func testNeverADanglingBackslash() {
        XCTAssertEqual(value(#"{"translation": "a\"#), "a")
        XCTAssertEqual(value(#"{"translation": "a\\"#), "a\\")
        XCTAssertEqual(value(#"{"translation": "a\\\"#), "a\\")
    }

    func testBackTranslationFirst() {
        let text = #"{"back_translation": "x \"translation\": \"no\" {[", "translation": "yes"}"#
        XCTAssertNil(value(String(text.prefix(40))))
        XCTAssertEqual(value(text), "yes")
    }

    func testWhitespaceAroundTheColon() {
        XCTAssertEqual(value("{ \"translation\" : \"Hi"), "Hi")
        XCTAssertEqual(value("{\n  \"translation\"\n\t:\n \"Hi"), "Hi")
    }

    func testOtherValuesAreSkipped() {
        XCTAssertEqual(value(#"{"n": 1, "o": {"translation": "no", "a": ["}", "\""]}, "t": true, "translation": "yes"}"#), "yes")
    }

    func testTheValueStopsAtItsClosingQuote() {
        XCTAssertEqual(value(#"{"translation": "Hi", "translation": "again"}"#), "Hi")
    }

    func testProseBeforeTheObject() {
        XCTAssertEqual(value(#"Sure: {"translation": "Hi", "back_translation": ""} done"#), "Hi")
    }

    func testAnySplitGivesTheSameValue() {
        for text in [
            #"{"translation": "Thanks for today", "back_translation": "오늘 고마워"}"#,
            #"{"back_translation": "x", "translation": "a\"b\\c\u00e9\ud83d\ude00\n"}"#,
            #"{ "translation" : "café 😀 → ok" }"#,
            #"{"translation": "x\ud83dy"#,
        ] {
            assertAnySplitAgrees(text)
        }
    }

    func testTheFullTextGivesWhatParseGives() throws {
        for text in [
            #"{"translation": "Thanks for today", "back_translation": "오늘 고마워"}"#,
            #"{"back_translation": "x", "translation": "a\"b\\c\/\u00e9\ud83d\ude00\n\t"}"#,
            #"{ "translation" : "Hi" , "back_translation" : "" }"#,
            #"Sure: {"translation": "Hi", "back_translation": ""} done"#,
            String(data: try JSONSerialization.data(withJSONObject: [
                "translation": "\u{1}\u{1F}\"\\/\u{7F}\u{2028}é😀 한국어", "back_translation": "b",
            ]), encoding: .utf8)!,
        ] {
            let parsed = try XCTUnwrap(ActionAPI.jsonObject(in: text)?["translation"] as? String, text)
            XCTAssertEqual(value(text), parsed, text)
        }
    }
}
