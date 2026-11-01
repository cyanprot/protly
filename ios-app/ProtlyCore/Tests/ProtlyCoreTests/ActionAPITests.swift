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
        XCTAssertEqual(b["stream"] as? Bool, true)
        let msg = (b["messages"] as! [[String: Any]])[0]
        XCTAssertEqual(msg["content"] as? String, "MODE: in\n\nTEXT:\nsee you soon")
    }

    func testOutAndFixAreOpusAdaptive() throws {
        for mode in [ActionMode.out, .fix] {
            let b = json(try ActionAPI.body(mode: mode, text: "x", system: "S"))
            XCTAssertEqual(b["model"] as? String, "claude-opus-5-5")
            XCTAssertEqual((b["thinking"] as? [String: String])?["type"], "adaptive")
            XCTAssertEqual(b["stream"] as? Bool, true)
            XCTAssertEqual(b["max_tokens"] as? Int, 16000)
            let msg = (b["messages"] as! [[String: Any]])[0]
            let target = mode == .out ? "\nTARGET: English" : ""
            XCTAssertEqual(msg["content"] as? String, "MODE: \(mode.rawValue)\(target)\n\nDRAFT:\nx")
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

    /// The part of parse after the status, shared by the whole-body path and the stream.
    func testResultFromTheTextAndTheStopReason() {
        let text = #"{"translation":"Hi","back_translation":"안녕"}"#
        let ok = ActionResult(translation: "Hi", backTranslation: "안녕")
        XCTAssertEqual(try ActionAPI.result(text: text, stopReason: "end_turn").get(), ok)
        XCTAssertEqual(try ActionAPI.result(text: text, stopReason: nil).get(), ok)
        XCTAssertEqual(ActionAPI.result(text: text, stopReason: "refusal").failureKind, .refused)
        XCTAssertEqual(ActionAPI.result(text: text, stopReason: "max_tokens").failureKind, .truncated)
        XCTAssertEqual(ActionAPI.result(text: #"{"translation":"Hi""#, stopReason: "end_turn").failureKind, .parse)
        XCTAssertEqual(ActionAPI.result(text: #"{"translation":" ","back_translation":""}"#, stopReason: nil).failureKind, .parse)
    }

    /// keyboard-ui 003 (P4): Retry only where trying again can work, and exactly those lines say to try again.
    func testRetryOnlyWhereItCanWork() {
        let retry: Set<ActionError.Kind> = [.network, .timeout, .overloaded, .rate, .server, .parse]
        for k in [ActionError.Kind.auth, .spendLimit, .rate, .overloaded, .server, .badRequest, .network, .timeout,
                  .refused, .truncated, .parse, .tooLong, .noKey, .setup] {
            XCTAssertEqual(ActionError(k).canRetry, retry.contains(k), "\(k)")
            // Each line says what happened and what to do next: at least two sentences.
            let m = ActionError(k).message
            XCTAssertGreaterThanOrEqual(m.components(separatedBy: ". ").count, 2, m)
            XCTAssertTrue(m.hasSuffix("."), m)
            XCTAssertEqual(m.lowercased().contains("try again"), retry.contains(k), m)
        }
    }

    /// A stream's error event type -> the kind shown; the spend limit is read from the body as for a 429.
    func testStreamErrorTypes() {
        let table: [(String, ActionError.Kind)] = [
            ("invalid_request_error", .badRequest), ("authentication_error", .auth), ("permission_error", .auth),
            ("not_found_error", .badRequest), ("request_too_large", .badRequest), ("rate_limit_error", .rate),
            ("api_error", .server), ("overloaded_error", .overloaded), ("timeout_error", .timeout),
            ("something_new", .server), ("", .server),
        ]
        for (type, kind) in table {
            XCTAssertEqual(ActionAPI.kind(streamError: type, body: Data()), kind, type)
        }
        let spend = Data(#"{"type": "error", "error": {"type": "rate_limit_error", "details": {"error_code": "enforced_spend_limit_reached"}}}"#.utf8)
        XCTAssertEqual(ActionAPI.kind(streamError: "rate_limit_error", body: spend), .spendLimit)
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

    func testOutNamesItsTargetAndAPrefixPicksIt() {
        XCTAssertEqual(ActionAPI.userMessage(mode: .out, text: "내일 봐"), "MODE: out\nTARGET: English\n\nDRAFT:\n내일 봐")
        XCTAssertEqual(ActionAPI.userMessage(mode: .out, text: "ru: 노트 고마워"), "MODE: out\nTARGET: Russian\n\nDRAFT:\n노트 고마워")
        XCTAssertEqual(ActionAPI.userMessage(mode: .out, text: "en: 내일 봐"), "MODE: out\nTARGET: English\n\nDRAFT:\n내일 봐")
        XCTAssertEqual(ActionAPI.userMessage(mode: .out, text: "ok: 내일 봐"), "MODE: out\nTARGET: English\n\nDRAFT:\nok: 내일 봐")
        XCTAssertEqual(ActionAPI.userMessage(mode: .in, text: "ru: привет"), "MODE: in\n\nTEXT:\nru: привет")
        XCTAssertEqual(ActionAPI.userMessage(mode: .fix, text: "no: see you"), "MODE: fix\n\nDRAFT:\nno: see you")
    }

    func testAKoPrefixPolishesAKoreanDraft() {
        XCTAssertEqual(ActionAPI.mode(forDraft: "ko: 낼 봐"), .fix)
        XCTAssertEqual(ActionAPI.mode(forDraft: " KO:낼 봐"), .fix)
        XCTAssertEqual(ActionAPI.userMessage(mode: .fix, text: "ko: 낼 봐 ㅋㅋ"), "MODE: fix\n\nDRAFT:\n낼 봐 ㅋㅋ")
        XCTAssertTrue(ActionAPI.isKoreanPolish("ko: 낼 봐"))
        // Nothing Korean after it: a draft as today, prefix kept.
        XCTAssertFalse(ActionAPI.isKoreanPolish("ko: see you"))
        XCTAssertEqual(ActionAPI.userMessage(mode: .fix, text: "ko: see you"), "MODE: fix\n\nDRAFT:\nko: see you")
        XCTAssertEqual(ActionAPI.mode(forDraft: "ko:"), .fix)
        // Any other prefix, or ko: later in the draft, still translates.
        XCTAssertEqual(ActionAPI.mode(forDraft: "ru: 낼 봐"), .out)
        XCTAssertEqual(ActionAPI.mode(forDraft: "낼 봐 ko: 응"), .out)
    }
}
