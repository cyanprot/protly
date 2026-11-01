import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLError on Linux
#endif

/// One step of a streamed action: the whole translation so far (never a delta), then exactly one `done` or
/// `failed`, last.
public enum ActionUpdate: Sendable, Equatable {
    case partial(String)
    case done(ActionResult)
    case failed(ActionError)
}

extension ActionAPI {
    /// The updates of one streamed call. `open` builds and sends the request (throwing an ActionError when it cannot
    /// be built) and returns the HTTP status, the reply's bytes and a way to stop the download; the keyboard's ActionClient passes URLSession's, the tests pass fakes.
    /// Runs off the caller's actor. Ending the consumer (its task cancelled, or the stream dropped) cancels the
    /// producer and so the download; a cancel never shows as an error. The buffer keeps the newest two updates: a
    /// partial carries the whole text so far, so a dropped older one loses nothing, and the final update is yielded
    /// last, so the buffer always ends with the newest partial and then the result. A consumer that paces itself
    /// (the keyboard redraws the card at most 20 times a second) still gets all the text before a failure, which
    /// carries none.
    /// `SendableMetatype`: the producer task is generic over the byte sequence's type.
    public static func updates<S: AsyncSequence & SendableMetatype>(
        limit: Int = maxResponseBytes,
        open: @escaping @Sendable () async throws -> (status: Int, bytes: S, stop: @Sendable () -> Void)
    ) -> AsyncStream<ActionUpdate> where S.Element == UInt8 {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let producer = Task {
                defer { continuation.finish() }
                do {
                    let reply = try await open()
                    defer { reply.stop() }  // on every way out: stop the download now, not when it is released
                    try await drive(status: reply.status, bytes: reply.bytes, limit: limit) { continuation.yield($0) }
                } catch {
                    if let e = failure(for: error) { continuation.yield(.failed(e)) }
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// Reads one reply and yields its updates. A 200 is a stream: partials as the translation grows, then the result. Any other status is a plain JSON error
    /// body. `limit` counts raw bytes; past it the reply is not read (`.parse`). A stream that ends with no stop
    /// reason and no whole reply was cut off on the way: `.network`, so Retry is offered. Throws what the bytes
    /// throw, and CancellationError when cancelled.
    static func drive<S: AsyncSequence>(status: Int, bytes: S, limit: Int, yield: (ActionUpdate) -> Void) async throws
    where S.Element == UInt8 {
        guard status == 200 else {
            guard let body = try await collect(bytes, limit: limit) else { return yield(.failed(ActionError(.parse))) }
            return yield(.failed(ActionError(kind(status: status, body: body))))
        }
        var stream = ActionStream()
        var partial = PartialTranslation()
        var text = ""
        var stopReason: String?
        var count = 0
        /// The bytes since the last line end: the parser is fed whole lines, not single bytes.
        var line: [UInt8] = []
        for try await byte in bytes {
            count += 1
            guard count <= limit else { return yield(.failed(ActionError(.parse))) }
            if count % 4096 == 0 { try Task.checkCancellation() }
            line.append(byte)
            guard byte == 0x0A || byte == 0x0D else { continue }
            let events = stream.feed(line)
            line.removeAll(keepingCapacity: true)
            for event in events {
                switch event {
                case .text(let t):
                    text += t
                    // Thinking, pings and the back translation change nothing: no update for them.
                    // The opening quote alone is no text yet: the card opens at the first word.
                    if partial.append(t), let value = partial.value, !value.isEmpty { yield(.partial(value)) }
                case .stop(let reason):
                    stopReason = reason
                case let .error(type, body):
                    return yield(.failed(ActionError(kind(streamError: type, body: body))))
                }
            }
        }
        try Task.checkCancellation()
        switch result(text: text, stopReason: stopReason) {
        case .success(let r):
            yield(.done(r))
        case .failure(let e):
            yield(.failed(stopReason == nil && e.kind == .parse ? ActionError(.network) : e))
        }
    }

    /// A thrown error as the user sees it. nil for a cancel (Cancel, the keyboard hiding, a Retry): no error shows.
    /// An ActionError (a request that could not be built) shows as it is.
    public static func failure(for error: any Error) -> ActionError? {
        if let e = error as? ActionError { return e }
        if error is CancellationError { return nil }
        if let e = error as? URLError {
            if e.code == .cancelled { return nil }
            if e.code == .timedOut { return ActionError(.timeout) }
        }
        return ActionError(.network)
    }
}
