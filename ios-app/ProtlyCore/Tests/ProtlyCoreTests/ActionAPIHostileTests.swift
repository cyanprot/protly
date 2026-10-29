import Foundation
import XCTest
@testable import ProtlyCore

// Whatever comes back, parse returns a result or one of the fixed errors: no trap, no raw body shown.
final class ActionAPIHostileTests: XCTestCase {
    private func kind(_ status: Int, _ body: Data) -> ActionError.Kind? {
        ActionAPI.parse(status: status, body: body).failureKind
    }
    private func kind(_ status: Int, _ s: String) -> ActionError.Kind? { kind(status, Data(s.utf8)) }

    /// A 200 reply whose text block is `text`.
    private func reply(_ text: String, stop: String = "end_turn") -> Data {
        let obj: [String: Any] = ["stop_reason": stop, "content": [["type": "text", "text": text]]]
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    func testBodiesThatAreNotJSONObjects() {
        XCTAssertEqual(kind(200, Data()), .parse)
        XCTAssertEqual(kind(200, Data([0xFF, 0xFE, 0x00, 0x7B, 0x80])), .parse)  // not UTF-8
        XCTAssertEqual(kind(200, Data(#"{"content":[]}"#.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })), .parse)
        for s in ["null", "[]", "42", #""text""#, "{", #"{"content":"#, "\u{0}"] {
            XCTAssertEqual(kind(200, s), .parse, s)
        }
    }

    func testDeeplyNestedJSONIsRefusedNotACrash() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        XCTAssertEqual(kind(200, deep), .parse)
        XCTAssertEqual(kind(200, #"{"content":"# + deep + "}"), .parse)
        // The same nesting inside the model's text.
        XCTAssertEqual(kind(200, reply("{\"translation\":" + deep + "}")), .parse)
    }

    func testWrongShapes() {
        let cases = [
            #"{"content":"text"}"#,
            #"{"content":{"type":"text","text":"x"}}"#,
            #"{"content":[1,null,"x",[]]}"#,
            #"{"content":[{"type":"text","text":42}]}"#,
            #"{"content":[{"type":"text"}]}"#,
            #"{"content":[{"type":7,"text":"{\"translation\":\"Hi\",\"back_translation\":\"\"}"}]}"#,
            #"{"content":[{"type":"tool_use","text":"{\"translation\":\"Hi\",\"back_translation\":\"\"}"}]}"#,
            #"{"stop_reason":42,"content":[]}"#,
        ]
        for c in cases { XCTAssertEqual(kind(200, c), .parse, c) }
    }

    func testModelTextThatIsNotTheTwoFields() {
        for text in [
            "", "   ", "no json here", "}{", "{", "}", "{}", "[]",
            #"{"translation":42,"back_translation":""}"#,
            #"{"translation":null,"back_translation":""}"#,
            #"{"translation":"Hi"}"#,
            #"{"translation":"Hi","back_translation":7}"#,
            #"{"translation":"\n\t ","back_translation":""}"#,
            #"["translation","back_translation"]"#,
        ] {
            XCTAssertEqual(kind(200, reply(text)), .parse, text)
        }
    }

    func testOddButValidTranslationsPassThroughUnchanged() throws {
        // Markup, script-looking text, bidi overrides, zero-width and NUL are just text: shown and inserted as is.
        for t in ["<b>hi</b><script>alert(1)</script>", "\u{202E}olleh\u{202C}", "a\u{200B}b\u{FEFF}c", "x\u{0}y", "👨‍👩‍👧🇰🇷", "e\u{301}"] {
            let text = String(data: try JSONSerialization.data(withJSONObject: ["translation": t, "back_translation": t]), encoding: .utf8)!
            let r = try ActionAPI.parse(status: 200, body: reply(text)).get()
            XCTAssertEqual(r.translation, t)
            XCTAssertEqual(r.backTranslation, t)
        }
    }

    func testFirstAndLastBraceWinWhenTheTextHasSeveral() {
        // The outermost {...} of two objects is not valid JSON: an error, never half of one object.
        let two = #"{"translation":"A","back_translation":""} and {"translation":"B","back_translation":""}"#
        XCTAssertEqual(kind(200, reply(two)), .parse)
    }

    func testStopReasonsWinOverAnyText() {
        let ok = #"{"translation":"Hi","back_translation":""}"#
        XCTAssertEqual(kind(200, reply(ok, stop: "refusal")), .refused)
        XCTAssertEqual(kind(200, reply(ok, stop: "max_tokens")), .truncated)
        XCTAssertNil(kind(200, reply(ok, stop: "something_new")))
    }

    func testErrorStatusesNeverParseTheBodyAsAReply() {
        let ok = String(data: reply(#"{"translation":"Hi","back_translation":""}"#), encoding: .utf8)!
        XCTAssertEqual(kind(400, ok), .badRequest)
        XCTAssertEqual(kind(500, ok), .server)
        XCTAssertEqual(kind(0, ok), .badRequest)       // not an HTTP response
        XCTAssertEqual(kind(-1, ""), .badRequest)
        XCTAssertEqual(kind(201, ok), .badRequest)
        XCTAssertEqual(kind(403, ok), .auth)
        // A 429 with any body shape is a rate limit unless it names the spend limit.
        for body in ["", "x", "[]", #"{"error":"x"}"#, #"{"error":{"details":"x"}}"#, #"{"error":{"details":{"error_code":7}}}"#] {
            XCTAssertEqual(kind(429, body), .rate, body)
        }
    }

    func testErrorMessagesAreFixedText() {
        // A key-shaped string or a request echo in the body never reaches the message.
        let echo = #"{"error":{"message":"sk-ant-api03-SECRET and your text: 내 비밀"}}"#
        for status in [400, 401, 403, 429, 500, 529] {
            let r = ActionAPI.parse(status: status, body: Data(echo.utf8))
            guard case .failure(let e) = r else { return XCTFail("\(status)") }
            XCTAssertFalse(e.message.contains("sk-ant"))
            XCTAssertFalse(e.message.contains("비밀"))
        }
        for k in [ActionError.Kind.auth, .spendLimit, .rate, .overloaded, .server, .badRequest, .network, .timeout,
                  .refused, .truncated, .parse, .tooLong, .noKey, .setup] {
            XCTAssertFalse(ActionError(k).message.isEmpty)
            XCTAssertFalse(ActionError(k).message.contains("sk-ant"))
        }
    }

    func testALongValidReplyParses() throws {
        // Up to the size of a full 16000-token reply.
        let t = String(repeating: "번역된 문장입니다. ", count: 8_000)
        let text = String(data: try JSONSerialization.data(withJSONObject: ["translation": t, "back_translation": ""]), encoding: .utf8)!
        XCTAssertLessThan(reply(text).count, ActionAPI.maxResponseBytes)
        XCTAssertEqual(try ActionAPI.parse(status: 200, body: reply(text)).get().translation, t)
    }
}
