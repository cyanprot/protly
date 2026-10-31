import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLError on Linux
#endif
import XCTest
@testable import ProtlyCore

/// Scripted byte chunks, then the end or an error. Each chunk is followed by a yield, as a network read would be.
private struct Chunks: AsyncSequence, Sendable {
    typealias Element = UInt8
    let chunks: [[UInt8]]
    var error: (any Error & Sendable)?

    init(_ text: String, chunk: Int = 64, error: (any Error & Sendable)? = nil) {
        let bytes = Array(text.utf8)
        chunks = stride(from: 0, to: bytes.count, by: chunk).map { Array(bytes[$0..<Swift.min($0 + chunk, bytes.count)]) }
        self.error = error
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let chunks: [[UInt8]]
        let error: (any Error & Sendable)?
        var chunk = 0
        var index = 0

        mutating func next() async throws -> UInt8? {
            while chunk < chunks.count, index >= chunks[chunk].count {
                chunk += 1
                index = 0
                await Task.yield()
            }
            guard chunk < chunks.count else {
                if let error { throw error }
                return nil
            }
            defer { index += 1 }
            return chunks[chunk][index]
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(chunks: chunks, error: error) }
}

/// Opens once (the first time next() is called) and stays open until cancelled.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var open = false

    func wait() async {
        await withCheckedContinuation { c in
            let resume = lock.withLock { () -> Bool in
                if open { return true }
                waiter = c
                return false
            }
            if resume { c.resume() }
        }
    }

    func release() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            open = true
            defer { waiter = nil }
            return waiter
        }
        c?.resume()
    }
}

/// A scripted prefix, then a read that never ends until its task is cancelled; the cancel fulfils `cancelled`.
private struct Endless: AsyncSequence, Sendable {
    typealias Element = UInt8
    let prefix: [UInt8]
    let gate = Gate()
    let cancelled: XCTestExpectation

    struct AsyncIterator: AsyncIteratorProtocol {
        let prefix: [UInt8]
        let gate: Gate
        let cancelled: XCTestExpectation
        var index = 0

        mutating func next() async -> UInt8? {
            if index < prefix.count {
                defer { index += 1 }
                return prefix[index]
            }
            let gate = gate, cancelled = cancelled
            await withTaskCancellationHandler {
                await gate.wait()
            } onCancel: {
                cancelled.fulfill()
                gate.release()
            }
            return nil
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(prefix: prefix, gate: gate, cancelled: cancelled) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func add() { lock.withLock { n += 1 } }
}

final class ActionStreamingTests: XCTestCase {
    private let ok = ActionResult(translation: "Thanks for today", backTranslation: "오늘 고마워")

    /// Every update the driver yields, in order (no buffer in between).
    private func drive(_ bytes: Chunks, status: Int = 200, limit: Int = ActionAPI.maxResponseBytes) async -> [ActionUpdate] {
        var out: [ActionUpdate] = []
        do {
            try await ActionAPI.drive(status: status, bytes: bytes, limit: limit) { out.append($0) }
        } catch {
            if let e = ActionAPI.failure(for: error) { out.append(.failed(e)) }
        }
        return out
    }

    private func consume(_ stream: AsyncStream<ActionUpdate>) async -> [ActionUpdate] {
        var out: [ActionUpdate] = []
        for await u in stream { out.append(u) }
        return out
    }

    func testPartialsGrowThenTheResult() async {
        let updates = await drive(Chunks(SSE.reply(SSE.pieces)))
        // The third piece is the back translation: the translation does not change, so no partial.
        XCTAssertEqual(updates, [.partial("Thanks "), .partial("Thanks for today"), .done(ok)])
    }

    func testAnyChunkingGivesTheSameUpdates() async {
        let s = SSE.reply(SSE.pieces)
        let expected = await drive(Chunks(s))
        for size in [1, 3, 1000] {
            let got = await drive(Chunks(s, chunk: size))
            XCTAssertEqual(got, expected, "chunks of \(size)")
        }
    }

    /// The card opens at the first word: the opening quote alone yields nothing.
    func testAnEmptyTranslationSoFarYieldsNothing() async {
        let s = SSE.text(#"{"translation": ""#) + SSE.text("Hi") + SSE.text(#"", "back_translation": ""}"#)
            + SSE.stop("end_turn")
        let updates = await drive(Chunks(s))
        XCTAssertEqual(updates, [.partial("Hi"), .done(ActionResult(translation: "Hi", backTranslation: ""))])
    }

    func testThinkingAndPingsBetweenDeltasYieldNothing() async {
        let s = SSE.start + SSE.text(#"{"translation": "A"#) + SSE.thinking + SSE.event("ping", #"{"type": "ping"}"#)
            + SSE.text(#"", "back_translation": "B"}"#) + SSE.stop("end_turn") + SSE.end
        let updates = await drive(Chunks(s))
        XCTAssertEqual(updates, [.partial("A"), .done(ActionResult(translation: "A", backTranslation: "B"))])
    }

    func testStopReasonsAfterText() async {
        let truncated = await drive(Chunks(SSE.reply([#"{"translation": "Thanks"#], stop: "max_tokens")))
        XCTAssertEqual(truncated, [.partial("Thanks"), .failed(ActionError(.truncated))])
        let refused = await drive(Chunks(SSE.reply([], stop: "refusal")))
        XCTAssertEqual(refused, [.failed(ActionError(.refused))])
    }

    func testAStreamThatEndsWithoutAStopReason() async {
        let whole = await drive(Chunks(SSE.start + SSE.text(#"{"translation": "Hi", "back_translation": ""}"#)))
        XCTAssertEqual(whole, [.partial("Hi"), .done(ActionResult(translation: "Hi", backTranslation: ""))])
        let cut = await drive(Chunks(SSE.start + SSE.text(#"{"translation": "Hi"#)))
        XCTAssertEqual(cut, [.partial("Hi"), .failed(ActionError(.parse))])
    }

    func testAnErrorEventMidStream() async {
        let s = SSE.start + SSE.text(#"{"translation": "Hi"#)
            + SSE.event("error", #"{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#)
            + SSE.text(" more")
        let updates = await drive(Chunks(s))
        XCTAssertEqual(updates, [.partial("Hi"), .failed(ActionError(.overloaded))])
    }

    func testAnErrorEventKeepsTheSpendLimit() async {
        let data = #"{"type": "error", "error": {"type": "rate_limit_error", "message": "x", "details": {"error_code": "enforced_spend_limit_reached"}}}"#
        let spend = await drive(Chunks(SSE.event("error", data)))
        XCTAssertEqual(spend, [.failed(ActionError(.spendLimit))])
        let rate = await drive(Chunks(SSE.event("error", #"{"type": "error", "error": {"type": "rate_limit_error"}}"#)))
        XCTAssertEqual(rate, [.failed(ActionError(.rate))])
    }

    func testAReplyThatIsNot200IsAPlainErrorBody() async {
        let spend = #"{"type":"error","error":{"type":"rate_limit_error","details":{"error_code":"enforced_spend_limit_reached"}}}"#
        let a = await drive(Chunks(spend), status: 429)
        XCTAssertEqual(a, [.failed(ActionError(.spendLimit))])
        let b = await drive(Chunks("{}"), status: 529)
        XCTAssertEqual(b, [.failed(ActionError(.overloaded))])
        // Even a body shaped like a stream is never read as one.
        let c = await drive(Chunks(SSE.reply(SSE.pieces)), status: 401)
        XCTAssertEqual(c, [.failed(ActionError(.auth))])
        // The error body is read bounded too.
        let d = await drive(Chunks(String(repeating: "x", count: 101)), status: 500, limit: 100)
        XCTAssertEqual(d, [.failed(ActionError(.parse))])
    }

    func testTheCapCountsTheRawStreamBytes() async {
        // Framing and thinking count: the reply is mostly framing.
        let s = SSE.reply(SSE.pieces)
        let size = s.utf8.count
        let exact = await drive(Chunks(s, chunk: 4096), limit: size)
        XCTAssertEqual(exact.last, .done(ok))
        let over = await drive(Chunks(s, chunk: 4096), limit: size - 1)
        XCTAssertEqual(over.last, .failed(ActionError(.parse)))
    }

    func testTheRealCapStopsAStreamJustOverIt() async {
        // A comment line pads the reply to exactly maxResponseBytes, then one byte more.
        let reply = SSE.reply(SSE.pieces)
        let pad = ActionAPI.maxResponseBytes - reply.utf8.count - 3
        let exact = ":" + String(repeating: "x", count: pad) + "\n\n" + reply
        XCTAssertEqual(exact.utf8.count, ActionAPI.maxResponseBytes)
        let atCap = await drive(Chunks(exact, chunk: 65536))
        XCTAssertEqual(atCap.last, .done(ok))
        let overCap = await drive(Chunks(":x" + exact.dropFirst(), chunk: 65536))
        XCTAssertEqual(overCap, [.partial("Thanks "), .partial("Thanks for today"), .failed(ActionError(.parse))])
    }

    func testAFullLengthReplyFitsUnderTheCap() {
        // The plan's sizing: one text_delta event per token, 16000 tokens, framing included.
        let event = SSE.text("tok", index: 1)
        XCTAssertLessThan(event.utf8.count * 16000, ActionAPI.maxResponseBytes)
    }

    func testThrownErrors() async {
        let text = SSE.text(#"{"translation": "Hi"#)
        let timeout = await drive(Chunks(text, error: URLError(.timedOut)))
        XCTAssertEqual(timeout, [.partial("Hi"), .failed(ActionError(.timeout))])
        let offline = await drive(Chunks(text, error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(offline, [.partial("Hi"), .failed(ActionError(.network))])
        struct Other: Error {}
        let other = await drive(Chunks("", error: Other()))
        XCTAssertEqual(other, [.failed(ActionError(.network))])
    }

    /// Cancel, the keyboard hiding or a Retry: the stream just ends, never a visible network error.
    func testCancellationIsNotANetworkError() async {
        let text = SSE.text(#"{"translation": "Hi"#)
        let a = await drive(Chunks(text, error: CancellationError()))
        XCTAssertEqual(a, [.partial("Hi")])
        let b = await drive(Chunks(text, error: URLError(.cancelled)))
        XCTAssertEqual(b, [.partial("Hi")])
        XCTAssertNil(ActionAPI.failure(for: CancellationError()))
        XCTAssertNil(ActionAPI.failure(for: URLError(.cancelled)))
        XCTAssertEqual(ActionAPI.failure(for: URLError(.timedOut)), ActionError(.timeout))
        XCTAssertEqual(ActionAPI.failure(for: URLError(.networkConnectionLost)), ActionError(.network))
    }

    func testTheStreamEndsWithExactlyOneResultLast() async {
        let stop = Counter()
        let stream = ActionAPI.updates { (200, Chunks(SSE.reply(SSE.pieces)), { stop.add() }) }
        let updates = await consume(stream)
        XCTAssertEqual(updates.last, .done(ok))
        XCTAssertEqual(updates.dropLast().filter { if case .partial = $0 { return false }; return true }, [])
        XCTAssertEqual(stop.value, 1, "the download is stopped on the way out")
    }

    /// A consumer that starts reading only after the producer is done still gets the final update: the buffer keeps
    /// the newest one. Partials may be dropped.
    func testASlowConsumerStillGetsTheResult() async {
        let produced = expectation(description: "the producer is done")
        let stream = ActionAPI.updates { (200, Chunks(SSE.reply(SSE.pieces)), { produced.fulfill() }) }
        await fulfillment(of: [produced], timeout: 10)
        let updates = await consume(stream)
        XCTAssertEqual(updates.last, .done(ok))
        XCTAssertEqual(updates.count, 1, "only the newest update is kept")
    }

    /// A request that cannot be built fails through the same stream (open throws the ActionError).
    func testAnActionErrorFromOpenIsShownAsIs() async {
        let noKey = await consume(ActionAPI.updates { () async throws -> (status: Int, bytes: Chunks, stop: @Sendable () -> Void) in
            throw ActionError(.noKey)
        })
        XCTAssertEqual(noKey, [.failed(ActionError(.noKey))])
        XCTAssertEqual(ActionAPI.failure(for: ActionError(.tooLong)), ActionError(.tooLong))
    }

    func testTheStreamReportsAFailureToOpen() async {
        let timeout = await consume(ActionAPI.updates { () async throws -> (status: Int, bytes: Chunks, stop: @Sendable () -> Void) in
            throw URLError(.timedOut)
        })
        XCTAssertEqual(timeout, [.failed(ActionError(.timeout))])
        let cancelled = await consume(ActionAPI.updates { () async throws -> (status: Int, bytes: Chunks, stop: @Sendable () -> Void) in
            throw URLError(.cancelled)
        })
        XCTAssertEqual(cancelled, [])
    }

    func testTheStreamStopsAnEarlyExit() async {
        let stop = Counter()
        let s = SSE.event("error", #"{"type": "error", "error": {"type": "api_error"}}"#) + SSE.reply(SSE.pieces)
        let updates = await consume(ActionAPI.updates { (200, Chunks(s), { stop.add() }) })
        XCTAssertEqual(updates, [.failed(ActionError(.server))])
        XCTAssertEqual(stop.value, 1)
    }

    /// Consumer cancel -> onTermination -> producer cancel: the read in progress is cancelled, not left running.
    func testCancellingTheConsumerCancelsTheDownload() async {
        let cancelled = expectation(description: "the read was cancelled")
        let first = expectation(description: "the first partial arrived")
        let bytes = Endless(prefix: Array(SSE.text(#"{"translation": "Hi"#).utf8), cancelled: cancelled)
        let stream = ActionAPI.updates { (200, bytes, {}) }
        let consumer = Task {
            var out: [ActionUpdate] = []
            for await u in stream {
                out.append(u)
                if out.count == 1 { first.fulfill() }
            }
            return out
        }
        await fulfillment(of: [first], timeout: 10)
        consumer.cancel()
        await fulfillment(of: [cancelled], timeout: 10)
        let updates = await consumer.value
        XCTAssertEqual(updates, [.partial("Hi")], "no failed after a cancel")
    }
}
