import Foundation
import XCTest
@testable import ProtlyCore

final class ActionAPITests: XCTestCase {
    private func json(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    func testInModeIsSonnetWithThinkingOff() throws {
        let b = json(try ActionAPI.body(mode: .in, text: "see you soon", system: "SYS"))
        XCTAssertEqual(b["model"] as? String, "claude-sonnet-5-5")
        XCTAssertEqual((b["thinking"] as? [String: String])?["type"], "between_tools")
        XCTAssertEqual(b["system"] as? String, "SYS")
        XCTAssertNil(b["temperature"])
        let msg = (b["messages"] as! [[String: Any]])[0]
        XCTAssertEqual(msg["content"] as? String, "MODE: in\n\nTEXT:\nsee you soon")
    }

    func testOutAndFixAreOpusAdaptive() throws {
        for mode in [ActionMode.out, .fix] {
            let b = json(try ActionAPI.body(mode: mode, text: "x", system: "S"))
            XCTAssertEqual(b["model"] as? String, "claude-opus-5-5")
            XCTAssertEqual((b["thinking"] as? [String: String])?["type"], "adaptive")
            let msg = (b["messages"] as! [[String: Any]])[0]
            XCTAssertEqual(msg["content"] as? String, "MODE: \(mode.rawValue)\n\nDRAFT:\nx")
        }
    }

    func testOutputIsTheTwoFieldSchema() throws {
        let b = json(try ActionAPI.body(mode: .out, text: "x", system: "S"))
        let cfg = b["output_config"] as! [String: Any]
        XCTAssertEqual(cfg["effort"] as? String, "low")
        let format = cfg["format"] as! [String: Any]
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = format["schema"] as! [String: Any]
        XCTAssertEqual(schema["required"] as? [String], ["translation", "back_translation"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testHeadersCarryTheWorkspace() {
        let h = ActionAPI.headers(apiKey: "k")
        XCTAssertEqual(h["anthropic-workspace-id"], "wrkspc_01MYddxiRDrvfHCyhebhtnQj")
        XCTAssertEqual(h["anthropic-version"], "2023-06-01")
        XCTAssertEqual(h["x-api-key"], "k")
    }

    func testParseSkipsThinkingAndJoinsText() {
        let body = data(#"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"translation\":\"Hi\","},{"type":"text","text":"\"back_translation\":\"안녕\"}"}]}"#)
        XCTAssertEqual(try ActionAPI.parse(status: 200, body: body).get(), ActionResult(translation: "Hi", backTranslation: "안녕"))
    }

    func testParseFindsJsonInsideProse() {
        let body = data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"Sure: {\"translation\":\"Hi\",\"back_translation\":\"\"} done"}]}"#)
        XCTAssertEqual(try ActionAPI.parse(status: 200, body: body).get().translation, "Hi")
    }

    func testParseErrors() {
        func kind(_ status: Int, _ s: String) -> ActionError.Kind? {
            if case .failure(let e) = ActionAPI.parse(status: status, body: data(s)) { return e.kind }
            return nil
        }
        XCTAssertEqual(kind(200, #"{"stop_reason":"refusal","content":[]}"#), .refused)
        XCTAssertEqual(kind(200, #"{"stop_reason":"max_tokens","content":[]}"#), .truncated)
        XCTAssertEqual(kind(200, #"{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"translation\":\" \",\"back_translation\":\"\"}"}]}"#), .parse)
        XCTAssertEqual(kind(200, "not json"), .parse)
        XCTAssertEqual(kind(401, "{}"), .auth)
        XCTAssertEqual(kind(429, #"{"error":{"details":{"error_code":"enforced_spend_limit_reached"}}}"#), .spendLimit)
        XCTAssertEqual(kind(429, "{}"), .rate)
        XCTAssertEqual(kind(529, "{}"), .overloaded)
        XCTAssertEqual(kind(503, "{}"), .server)
        XCTAssertEqual(kind(400, "{}"), .badRequest)
    }
}

final class ActionPromptTests: XCTestCase {
    func testBundledPromptIsTheKeyboardPrompt() throws {
        let p = try ActionAPI.bundledPrompt()
        XCTAssertTrue(p.hasPrefix("You translate and polish chat messages"))
        XCTAssertTrue(p.contains("MODE fix"))
    }

    func testDraftModeFollowsHangul() {
        XCTAssertEqual(ActionAPI.mode(forDraft: "내일 보자"), .out)
        XCTAssertEqual(ActionAPI.mode(forDraft: "ok 내일 봐"), .out)
        XCTAssertEqual(ActionAPI.mode(forDraft: "ㅋㅋ"), .out)
        XCTAssertEqual(ActionAPI.mode(forDraft: "see you tomorrow"), .fix)
    }
}
