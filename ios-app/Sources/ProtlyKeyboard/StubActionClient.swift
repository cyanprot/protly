#if PROTLY_CI_STUB
import Foundation
import ProtlyCore

/// CI only (keyboard-ui 003, Task 3.5): recorded streams for the simulator's result-card checks, offline and without a
/// key. `PROTLY_CI_STUB` is set only on the ProtlyCIKeyboard target in ios-app/CI/project.yml; the phone build never
/// defines it, so this file compiles to nothing there. The extension cannot read the host's launch arguments, and the
/// network checks call the real API through the same CI keyboard, so only a draft that starts with `marker` is
/// answered here; ActionClient.run asks before it touches the key. The bytes go through the same ProtlyCore driver
/// (ActionAPI.updates) as the real reply, so a cancel (`xmark`, Cancel, a hide) stops them the same way: every delay is
/// a `Task.sleep` whose CancellationError ends the read.
///
/// Scenarios (the word after the marker; ios-app/CI/UITests/CardChecks.swift reads the same texts):
/// - `ok`: a thinking block, a wait, then the translation in short deltas and the back translation; `end_turn`.
/// - `slow`: pings past the strip's 8 s line, then a long translation in one-second deltas (memory during a stream).
/// - `error`: an `overloaded_error` event before any text (the error line on the strip, with Retry).
/// - `cut`: part of the translation, then an `overloaded_error` event (the kept text with the error line under it).
/// Any other word: a plain 400 error body, as the API sends it.
enum StubActionClient {
    static let marker = "protly-stub "

    /// nil: not a marker draft, so the real client takes it.
    static func run(_ mode: ActionMode, text: String) -> AsyncStream<ActionUpdate>? {
        guard text.hasPrefix(marker) else { return nil }
        let word = String(text.dropFirst(marker.count).prefix { !$0.isWhitespace })
        let script = StubScript.named(word)
        return ActionAPI.updates {
            (status: script.status, bytes: StubBytes(chunks: script.chunks), stop: {})
        }
    }
}

/// One recorded reply: its HTTP status and its bytes, each chunk after its delay.
struct StubScript: Sendable {
    struct Chunk: Sendable {
        let delay: Duration
        let bytes: [UInt8]
    }

    let status: Int
    let chunks: [Chunk]

    static let okTranslation = "Thanks so much for today, it really helped me out."
    static let okBack = "오늘 정말 고마워, 큰 도움이 됐어."
    static let slowTranslation = "I wanted to say thank you again for everything you did this week. The notes you "
        + "shared saved me before the exam, and I owe you dinner whenever you are free."
    static let slowBack = "이번 주에 해준 거 다시 한번 고마워. 시험 전에 노트 덕분에 살았어, 시간 될 때 밥 살게."
    /// The text `cut` streams before its error: the card keeps exactly this.
    static let cutKept = "Thanks so much for today"

    static func named(_ word: String) -> StubScript {
        switch word {
        case "ok": return ok
        case "slow": return slow
        case "error": return error
        case "cut": return cut
        default:
            let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"unknown stub scenario"}}"#
            return StubScript(status: 400, chunks: [Chunk(delay: .milliseconds(500), bytes: Array(body.utf8))])
        }
    }

    private static var ok: StubScript {
        var c = [chunk(0, start + ping), chunk(2500, thinking("The writer thanks a friend."))]
        c.append(chunk(300, textStart))
        let deltas = [#"{"translation": ""#, "Thanks so much ", "for today, ", "it really ", "helped me out.",
                      #"", "back_translation": "#, #""오늘 정말 "#, #"고마워, 큰 도움이 됐어."}"#]
        c += deltas.map { chunk(800, textDelta($0)) }
        c.append(chunk(300, end("end_turn")))
        return StubScript(status: 200, chunks: c)
    }

    private static var slow: StubScript {
        var c = [chunk(0, start), chunk(500, thinking("A long thank-you note."))]
        // Pings only (no text) past the strip's 8 s "Still translating…" line.
        c += (0..<4).map { _ in chunk(2200, ping) }
        c.append(chunk(300, textStart))
        let words = slowTranslation.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var pieces = [#"{"translation": ""#]
        var i = 0
        while i < words.count {
            pieces.append(words[i..<min(i + 3, words.count)].joined(separator: " ") + (i + 3 < words.count ? " " : ""))
            i += 3
        }
        pieces += [#"", "back_translation": ""#, slowBack + #""}"#]
        c += pieces.map { chunk(1000, textDelta($0)) }
        c.append(chunk(300, end("end_turn")))
        return StubScript(status: 200, chunks: c)
    }

    private static var error: StubScript {
        StubScript(status: 200, chunks: [chunk(0, start), chunk(1500, ping), chunk(1000, errorEvent("overloaded_error"))])
    }

    private static var cut: StubScript {
        var c = [chunk(0, start), chunk(1500, textStart)]
        c += [#"{"translation": ""#, "Thanks so much ", "for today"].map { chunk(800, textDelta($0)) }
        c.append(chunk(1500, errorEvent("overloaded_error")))
        return StubScript(status: 200, chunks: c)
    }

    // MARK: Server-sent events, as the Messages API sends them

    private static func chunk(_ milliseconds: Int, _ text: String) -> Chunk {
        Chunk(delay: .milliseconds(milliseconds), bytes: Array(text.utf8))
    }

    private static func event(_ name: String, _ data: String) -> String { "event: \(name)\ndata: \(data)\n\n" }

    /// A JSON string literal (quotes and escapes), for a delta's text.
    private static func json(_ s: String) -> String {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static let start = event("message_start", #"{"type":"message_start","message":{"id":"msg_stub","type":"message","role":"assistant","content":[],"stop_reason":null}}"#)
    private static let ping = event("ping", #"{"type": "ping"}"#)
    private static let textStart = event("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#)

    private static func thinking(_ s: String) -> String {
        event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#)
            + event("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"# + json(s) + "}}")
            + event("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"c3R1Yg=="}}"#)
            + event("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
    }

    private static func textDelta(_ s: String) -> String {
        event("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"# + json(s) + "}}")
    }

    private static func end(_ reason: String) -> String {
        event("content_block_stop", #"{"type":"content_block_stop","index":1}"#)
            + event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"\#(reason)","stop_sequence":null}}"#)
            + event("message_stop", #"{"type":"message_stop"}"#)
    }

    private static func errorEvent(_ type: String) -> String {
        event("error", #"{"type":"error","error":{"type":"\#(type)","message":"stub"}}"#)
    }
}

/// The recorded bytes, one at a time like URLSession.AsyncBytes; each chunk waits its delay first.
struct StubBytes: AsyncSequence, Sendable {
    typealias Element = UInt8
    let chunks: [StubScript.Chunk]

    struct AsyncIterator: AsyncIteratorProtocol {
        let chunks: [StubScript.Chunk]
        var index = 0
        var bytes: [UInt8] = []
        var offset = 0

        mutating func next() async throws -> UInt8? {
            while offset == bytes.count {
                guard index < chunks.count else { return nil }
                let chunk = chunks[index]
                index += 1
                // Never try?: a cancelled call must stop here, not sleep on and stream into a closed card.
                if chunk.delay > .zero { try await Task.sleep(for: chunk.delay) }
                bytes = chunk.bytes
                offset = 0
            }
            defer { offset += 1 }
            return bytes[offset]
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(chunks: chunks) }
}
#endif
