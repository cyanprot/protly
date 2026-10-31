import Foundation

/// Server-sent events from the Messages API (`"stream": true`), read from raw bytes in any chunking.
/// Lines are split at the byte level, so a multi-byte UTF-8 character cut across two chunks is never decoded in
/// halves. Only the text deltas, the stop reason and an error event are kept; thinking, signatures, pings and the
/// block and message framing are read and dropped.
public struct ActionStream: Sendable {
    public enum Event: Sendable, Equatable {
        /// A `text_delta` from a `content_block_delta`.
        case text(String)
        /// `message_delta.delta.stop_reason`.
        case stop(String)
        /// An `error` event: `error.type` and the event's whole data, for ActionAPI.kind(status:body:).
        case error(type: String, body: Data)
    }

    /// The line being read, without its line end.
    private var line: [UInt8] = []
    /// The event being read: its `event:` name and its `data:` lines joined with "\n".
    private var name: String?
    private var data: [UInt8] = []
    private var hasData = false
    /// The last byte was a CR: an LF right after it ends no second line.
    private var afterCR = false

    public init() {}

    /// Reads the next bytes and returns the events they complete. Events are built only when a line ends.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [Event] {
        var out: [Event] = []
        for byte in bytes {
            switch byte {
            case 0x0A where afterCR:
                afterCR = false
            case 0x0A, 0x0D:
                afterCR = byte == 0x0D
                if let event = endLine() { out.append(event) }
            default:
                afterCR = false
                line.append(byte)
            }
        }
        return out
    }

    /// One line is complete: a blank line ends the event, any other line adds a field to it.
    private mutating func endLine() -> Event? {
        defer { line.removeAll(keepingCapacity: true) }
        guard !line.isEmpty else { return dispatch() }
        if line[0] == UInt8(ascii: ":") { return nil }  // a comment
        let colon = line.firstIndex(of: UInt8(ascii: ":")) ?? line.endIndex
        var value = line[min(colon + 1, line.endIndex)...]
        if value.first == UInt8(ascii: " ") { value = value.dropFirst() }
        switch String(decoding: line[..<colon], as: UTF8.self) {
        case "event":
            name = String(decoding: value, as: UTF8.self)
        case "data":
            if hasData { data.append(0x0A) }
            data.append(contentsOf: value)
            hasData = true
        default:
            break  // id, retry and unknown fields
        }
        return nil
    }

    /// The event names that can carry an Event.
    private static let kept: Set<String> = ["content_block_delta", "message_delta", "error"]
    private static let textDelta = Data("text_delta".utf8)

    private mutating func dispatch() -> Event? {
        defer {
            name = nil
            data.removeAll(keepingCapacity: true)
            hasData = false
        }
        guard hasData else { return nil }
        // Pings, thinking and the block and message framing are named: they are dropped without parsing.
        if let name, !Self.kept.contains(name) { return nil }
        let body = Data(data)
        // Thinking and signature deltas share the text deltas' event name: a byte search skips most of them.
        if name == "content_block_delta", body.range(of: Self.textDelta) == nil { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        switch name ?? obj["type"] as? String {
        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .text(text)
        case "message_delta":
            guard let reason = (obj["delta"] as? [String: Any])?["stop_reason"] as? String else { return nil }
            return .stop(reason)
        case "error":
            let type = (obj["error"] as? [String: Any])?["type"] as? String ?? ""
            return .error(type: type, body: body)
        default:
            return nil
        }
    }
}
