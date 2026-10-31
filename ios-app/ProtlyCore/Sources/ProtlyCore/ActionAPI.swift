import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLRequest on Linux
#endif

// Translate/Polish over the Anthropic Messages API: the request in, result or error out.
// This file builds the URLRequest, the session configuration and the redirect-refusing delegate, and reads and
// parses the reply bytes, but it never sends: the keyboard's ActionClient owns the URLSession and runs the request.

public enum ActionMode: String, Sendable, CaseIterable {
    case `in`   // someone else's text -> Korean
    case out    // the user's Korean draft -> English, or the language its prefix names ("ru: ...")
    case fix    // the user's English draft, polished; any other language in its own, Korean after "ko:"
}

public struct ActionResult: Sendable, Equatable {
    public let translation: String
    public let backTranslation: String
}

public struct ActionError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case auth, spendLimit, rate, overloaded, server, badRequest, network, timeout, refused, truncated, parse
        case tooLong, noKey, setup
    }
    public let kind: Kind
    /// Trying again can work: the network, a timeout, an overloaded API or a rate limit (P4).
    public var canRetry: Bool {
        switch kind {
        case .network, .timeout, .overloaded, .rate: return true
        default: return false
        }
    }
    /// One line for the strip or the card: what happened, then what to do next.
    public var message: String {
        switch kind {
        case .auth: return "API key rejected. Rebuild protly with a valid key."
        case .spendLimit: return "Monthly API spend limit reached. Raise the limit in the Console, or wait until it resets."
        case .rate: return "Rate limited. Try again in a moment."
        case .overloaded: return "The API is overloaded. Try again in a moment."
        case .server: return "The API had a server error. Try again."
        case .badRequest: return "The API rejected the request. Try a shorter text, or rebuild protly."
        case .network: return "Network error. Check the connection and try again."
        case .timeout: return "The model took too long. Try again."
        case .refused: return "The model declined this text. Edit it and try again."
        case .truncated: return "The reply was cut off. Try a shorter text."
        case .parse: return "The reply was not readable. Try again."
        case .tooLong: return "The text is too long. Try a shorter text."
        case .noKey: return "protly was built without an API key. Run make-secrets.sh and rebuild."
        case .setup: return "protly could not build the request. Rebuild protly."
        }
    }
    public init(_ kind: Kind) { self.kind = kind }
}

public enum ActionAPI {
    public static let url = "https://api.anthropic.com/v1/messages"
    /// Public, the same workspace as ios/protly.cherri. The phone key is org-level: the header is required.
    public static let workspaceID = "wrkspc_01MYddxiRDrvfHCyhebhtnQj"

    /// ios/keyboard-prompt.txt, bundled (copied in by scripts/sync-ios-app.mjs).
    public static func bundledPrompt() throws -> String {
        guard let url = Bundle.module.url(forResource: "keyboard-prompt", withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The action for the user's own draft: a Korean draft after "ko:" -> polish, else Korean anywhere ->
    /// translate out, else polish.
    public static func mode(forDraft text: String) -> ActionMode {
        isKoreanPolish(text) ? .fix : hasHangul(text) ? .out : .fix
    }

    /// "ko: 낼 봐": the writer asks for his Korean draft polished in Korean. Without Korean after the prefix the
    /// draft is handled as before, prefix and all.
    public static func isKoreanPolish(_ text: String) -> Bool {
        let p = Languages.prefix(of: text)
        return p.code == "ko" && hasHangul(p.text)
    }

    static func hasHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            !hangulFillers.contains(s.value) && hangulScalars.contains { $0.contains(s.value) }
        }
    }

    /// Invisible Hangul fillers (pasted as blank names and spacers on Instagram): not Korean text.
    static let hangulFillers: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0]

    /// Syllables, compatibility jamo, and the forms they take elsewhere: conjoining jamo (decomposed text,
    /// as in Mac file names), the jamo extensions, halfwidth jamo.
    static let hangulScalars: [ClosedRange<UInt32>] = [
        0xAC00...0xD7A3, 0x3131...0x318E, 0x1100...0x11FF, 0xA960...0xA97F, 0xD7B0...0xD7FF, 0xFFA0...0xFFDC,
    ]

    public static func model(for mode: ActionMode) -> String {
        mode == .in ? "claude-sonnet-5-5" : "claude-opus-5-5"
    }

    /// Longest text sent, in UTF-16 units. A longer text cannot fit the 16000-token reply anyway, and a
    /// multi-megabyte clipboard would cost the keyboard its memory and the account its money.
    public static let maxInputLength = 50_000
    /// Largest reply read, counted in raw bytes: for a stream that includes the event framing and the thinking
    /// deltas. One text_delta event is about 112 bytes of framing plus its text, so even one token per event, 16000
    /// tokens, is about 1.9 MB; anything bigger is not a reply.
    public static let maxResponseBytes = 2_000_000
    /// Seconds without a byte (the stream's pings and thinking deltas reset it), and the cap on the whole call,
    /// so a reply dribbled byte by byte still ends. URLSession enforces both and cancels the read.
    public static let idleTimeout: TimeInterval = 30
    public static let totalTimeout: TimeInterval = 90

    /// The request for one action, or the error to show without sending anything.
    public static func request(mode: ActionMode, text: String, system: String, apiKey: String) -> Result<URLRequest, ActionError> {
        // Printable ASCII, no space: anything else is not a key and could not travel as a header value.
        guard !apiKey.isEmpty, apiKey.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            return .failure(ActionError(.noKey))
        }
        guard text.utf16.count <= maxInputLength else { return .failure(ActionError(.tooLong)) }
        guard let url = URL(string: url), let body = try? body(mode: mode, text: text, system: system) else {
            return .failure(ActionError(.setup))
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: idleTimeout)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        for (name, value) in headers(apiKey: apiKey) { req.setValue(value, forHTTPHeaderField: name) }
        req.httpBody = body
        return .success(req)
    }

    /// The session for action requests: the text and the reply stay in memory, never in a cache or cookie store.
    public static func sessionConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = idleTimeout
        c.timeoutIntervalForResource = totalTimeout
        return c
    }

    public static func headers(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-workspace-id": workspaceID,
            "content-type": "application/json",
        ]
    }

    static var schema: [String: Any] { [
        "type": "object",
        "properties": ["translation": ["type": "string"], "back_translation": ["type": "string"]],
        "required": ["translation", "back_translation"],
        "additionalProperties": false,
    ] }

    /// Same shape as the extension and the Shortcut: thinking off on Sonnet is "between_tools", Opus is
    /// "adaptive"; effort low; JSON schema output; no temperature. Streamed (keyboard-ui 003).
    public static func body(mode: ActionMode, text: String, system: String) throws -> Data {
        let body: [String: Any] = [
            "model": model(for: mode),
            "max_tokens": 16000,
            "thinking": ["type": mode == .in ? "between_tools" : "adaptive"],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": system,
            "messages": [["role": "user", "content": userMessage(mode: mode, text: text)]],
            "stream": true,
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// MODE out names its TARGET: the language of the draft's prefix ("ru: 안녕", the prefix dropped), else
    /// English. MODE fix drops a "ko:" prefix (isKoreanPolish). The system prompt stays the same for every call.
    static func userMessage(mode: ActionMode, text: String) -> String {
        let p = Languages.prefix(of: text)
        switch mode {
        case .in:
            return "MODE: in\n\nTEXT:\n\(text)"
        case .out:
            let target = p.code == "ko" ? nil : p.code.flatMap(Languages.name(of:))
            return "MODE: out\nTARGET: \(target ?? "English")\n\nDRAFT:\n\(target == nil ? text : p.text)"
        case .fix:
            return "MODE: fix\n\nDRAFT:\n\(isKoreanPolish(text) ? p.text : text)"
        }
    }

    /// The reply's bytes, or nil once they pass `limit`: a huge or endless body never takes the keyboard's
    /// memory. Stops with CancellationError when the task is cancelled (Cancel, the keyboard hiding).
    public static func collect<S: AsyncSequence>(_ bytes: S, limit: Int = maxResponseBytes) async throws -> Data?
    where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { return nil }
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            data.append(byte)
        }
        return data
    }

    /// HTTP status and a whole (not streamed) body -> result. Thinking blocks are skipped; the answer is the joined
    /// text blocks.
    public static func parse(status: Int, body: Data) -> Result<ActionResult, ActionError> {
        guard body.count <= maxResponseBytes else { return .failure(ActionError(.parse)) }
        guard status == 200 else { return .failure(ActionError(kind(status: status, body: body))) }
        guard let resp = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .failure(ActionError(.parse))
        }
        let blocks = resp["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        return result(text: text, stopReason: resp["stop_reason"] as? String)
    }

    /// The model's text and its stop reason -> result: the whole-body path and the stream both end here.
    public static func result(text: String, stopReason: String?) -> Result<ActionResult, ActionError> {
        switch stopReason {
        case "refusal": return .failure(ActionError(.refused))
        case "max_tokens": return .failure(ActionError(.truncated))
        default: break
        }
        guard let obj = jsonObject(in: text),
              let translation = obj["translation"] as? String,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let back = obj["back_translation"] as? String
        else { return .failure(ActionError(.parse)) }
        return .success(ActionResult(translation: translation, backTranslation: back))
    }

    /// The HTTP status a stream's `error` event type stands for, so it maps through `kind(status:body:)` like an
    /// error body. An unknown type is a server error.
    static func status(forStreamError type: String) -> Int {
        switch type {
        case "invalid_request_error": return 400
        case "authentication_error": return 401
        case "permission_error": return 403
        case "not_found_error": return 404
        case "request_too_large": return 413
        case "rate_limit_error": return 429
        case "overloaded_error": return 529
        default: return 500  // api_error and anything new
        }
    }

    static func kind(status: Int, body: Data) -> ActionError.Kind {
        switch status {
        case 401, 403: return .auth
        case 429:
            let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            let details = (obj?["error"] as? [String: Any])?["details"] as? [String: Any]
            return details?["error_code"] as? String == "enforced_spend_limit_reached" ? .spendLimit : .rate
        case 529: return .overloaded
        case 500...: return .server
        default: return .badRequest
        }
    }

    /// The whole text as JSON, else the outermost {...} inside it.
    static func jsonObject(in text: String) -> [String: Any]? {
        if let d = text.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return o
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let d = String(text[start...end]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}

/// The action session's delegate: redirects are refused, because URLSession would replay every header,
/// the key included, to the new URL. The 3xx then reads as a rejected request.
public final class ActionSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
