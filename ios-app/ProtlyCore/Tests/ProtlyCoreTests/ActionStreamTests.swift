import Foundation
import XCTest
@testable import ProtlyCore

/// Recorded streams in the Anthropic Messages API's server-sent-events shape.
enum SSE {
    static func event(_ name: String, _ data: String, crlf: Bool = false) -> String {
        let nl = crlf ? "\r\n" : "\n"
        return "event: \(name)\(nl)data: \(data)\(nl)\(nl)"
    }

    static func text(_ t: String, index: Int = 1) -> String {
        let json = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta", "index": index, "delta": ["type": "text_delta", "text": t],
        ] as [String: Any], options: [.sortedKeys])
        return event("content_block_delta", String(decoding: json, as: UTF8.self))
    }

    static func stop(_ reason: String) -> String {
        event("message_delta", #"{"type": "message_delta", "delta": {"stop_reason": "\#(reason)", "stop_sequence": null}, "usage": {"output_tokens": 15}}"#)
    }

    static let start = event("message_start", #"{"type": "message_start", "message": {"id": "msg_1", "type": "message", "role": "assistant", "content": [], "model": "claude-opus-5-5", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}"#)
        + event("ping", #"{"type": "ping"}"#)

    static let thinking =
        event("content_block_start", #"{"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}"#)
        + event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "The user wants English."}}"#)
        + event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "EqQBCgIYAhIM"}}"#)
        + event("content_block_stop", #"{"type": "content_block_stop", "index": 0}"#)

    static let end = event("message_stop", #"{"type": "message_stop"}"#)

    /// A whole reply: thinking block, then a text block in pieces, then end_turn.
    static func reply(_ pieces: [String], stop reason: String = "end_turn") -> String {
        start + thinking
            + event("content_block_start", #"{"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}}"#)
            + pieces.map { text($0) }.joined()
            + event("content_block_stop", #"{"type": "content_block_stop", "index": 1}"#)
            + stop(reason) + end
    }

    static let pieces = [#"{"translation": "Thanks "#, #"for today", "back_"#, #"translation": "오늘 고마워"}"#]
}

final class ActionStreamTests: XCTestCase {
    private typealias Event = ActionStream.Event

    private func events(_ chunks: [[UInt8]]) -> [Event] {
        var s = ActionStream()
        return chunks.flatMap { s.feed($0) }
    }

    private func whole(_ s: String) -> [Event] { events([Array(s.utf8)]) }
    private func byteByByte(_ s: String) -> [Event] { events(Array(s.utf8).map { [$0] }) }

    func testAWholeStreamGivesTheTextAndTheStopReason() {
        let expected: [Event] = SSE.pieces.map { .text($0) } + [.stop("end_turn")]
        XCTAssertEqual(whole(SSE.reply(SSE.pieces)), expected)
    }

    func testAnyChunkingGivesTheSameEvents() {
        let s = SSE.reply(SSE.pieces)
        let expected = whole(s)
        XCTAssertEqual(byteByByte(s), expected)
        let bytes = Array(s.utf8)
        for size in [2, 3, 7, 64] {
            let chunks = stride(from: 0, to: bytes.count, by: size).map { Array(bytes[$0..<min($0 + size, bytes.count)]) }
            XCTAssertEqual(events(chunks), expected, "chunks of \(size)")
        }
    }

    func testCRLFAndBareCRLineEnds() {
        let crlf = SSE.event("content_block_delta",
                             #"{"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "Hi"}}"#, crlf: true)
        XCTAssertEqual(whole(crlf), [.text("Hi")])
        XCTAssertEqual(byteByByte(crlf), [.text("Hi")])
        let cr = crlf.replacingOccurrences(of: "\r\n", with: "\r")
        XCTAssertEqual(whole(cr), [.text("Hi")])
        XCTAssertEqual(byteByByte(cr), [.text("Hi")])
    }

    func testAKoreanCharacterSplitAcrossChunks() {
        let bytes = Array(SSE.text("고마워").utf8)
        // Split inside the first syllable's three UTF-8 bytes.
        let at = bytes.firstIndex { $0 >= 0xC0 }! + 1
        XCTAssertEqual(bytes[at] & 0xC0, 0x80, "the split is inside a multi-byte character")
        XCTAssertEqual(events([Array(bytes[..<at]), Array(bytes[at...])]), [.text("고마워")])
    }

    func testThinkingSignaturePingAndBlockEventsAreDropped() {
        XCTAssertEqual(whole(SSE.start + SSE.thinking + SSE.end), [])
    }

    func testAnErrorEvent() {
        let data = #"{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#
        XCTAssertEqual(whole(SSE.text("Hi") + SSE.event("error", data)),
                       [.text("Hi"), .error(type: "overloaded_error", body: Data(data.utf8))])
    }

    func testADataLineThatIsNotJSONIsSkipped() {
        for junk in ["not json", "{", "[1, 2]", "\"text\"", "{\"type\": \"content_block_delta\", \"delta\": 7}",
                     "{\"type\": \"content_block_delta\", \"delta\": {\"type\": \"text_delta\", \"text\": 7}}"] {
            XCTAssertEqual(whole(SSE.event("content_block_delta", junk) + SSE.text("ok")), [.text("ok")], junk)
        }
        XCTAssertEqual(whole(SSE.event("error", "oops") + SSE.text("ok")), [.text("ok")])
    }

    func testCommentsUnknownFieldsAndANullStopAreIgnored() {
        let s = ": keep-alive\n\nid: 7\nretry: 100\n\n"
            + SSE.event("message_delta", #"{"type": "message_delta", "delta": {"stop_reason": null}}"#)
            + SSE.text("ok")
        XCTAssertEqual(whole(s), [.text("ok")])
    }

    func testDataWithoutASpaceAndOnSeveralLines() {
        let s = "event:content_block_delta\ndata:{\"type\": \"content_block_delta\",\ndata: \"delta\": {\"type\": \"text_delta\", \"text\": \"a\\nb\"}}\n\n"
        XCTAssertEqual(whole(s), [.text("a\nb")])
    }

    func testAnEventWithoutAnEventLineUsesTheDataType() {
        let s = "data: {\"type\": \"content_block_delta\", \"delta\": {\"type\": \"text_delta\", \"text\": \"x\"}}\n\n"
        XCTAssertEqual(whole(s), [.text("x")])
    }

    func testAnUnfinishedEventWaitsForItsBlankLine() {
        var s = ActionStream()
        let event = Array(SSE.text("Hi").utf8)
        XCTAssertEqual(s.feed(event.dropLast()), [])
        XCTAssertEqual(s.feed(event.suffix(1)), [.text("Hi")])
    }
}
