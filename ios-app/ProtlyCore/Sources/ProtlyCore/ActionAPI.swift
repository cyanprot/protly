import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking  // URLRequest on Linux
#endif

// Translate/Polish over the Anthropic Messages API: the request in, result or error out.
// No networking here (FoundationNetworking differs on Linux): the keyboard sends the request.

public enum ActionMode: String, Sendable, CaseIterable {
    case `in`   // someone else's text -> Korean
    case out    // the user's Korean draft -> English
    case fix    // the user's English draft, polished
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
    /// Short English line for the bar.
    public var message: String {
        switch kind {
        case .auth: return "API key rejected. Rebuild protly with a valid key."
        case .spendLimit: return "Monthly API spend limit reached."
        case .rate: return "Rate limited. Try again in a moment."
        case .overloaded: return "The API is overloaded. Try again in a moment."
        case .server: return "The API had a server error. Try again."
        case .badRequest: return "The API rejected the request."
        case .network: return "Network error. Check the connection and try again."
        case .timeout: return "The model took too long. Try again."
        case .refused: return "The model declined this text."
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

    /// The action for the user's own draft: Korean anywhere -> translate out, else polish.
    public static func mode(forDraft text: String) -> ActionMode {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) } ? .out : .fix
    }

    public static func model(for mode: ActionMode) -> String {
        mode == .in ? "claude-sonnet-5-5" : "claude-opus-5-5"
    }

    /// Longest text sent, in UTF-16 units. A longer text cannot fit the 16000-token reply anyway, and a
    /// multi-megabyte clipboard would cost the keyboard its memory and the account its money.
    public static let maxInputLength = 50_000
    /// Largest reply read. 16000 tokens of output are about 100 KB; anything this big is not a reply.
    public static let maxResponseBytes = 2_000_000
    /// Seconds without a byte (the API sends the reply whole, so this is also the wait for it), and the
    /// cap on the whole request, so a reply dribbled byte by byte still ends.
    public static let idleTimeout: TimeInterval = 30
    public static let totalTimeout: TimeInterval = 90

    /// The request for one action, or the error to show without sending anything.
    public static func request(mode: ActionMode, text: String, system: String, apiKey: String) -> Result<URLRequest, ActionError> {
        guard !apiKey.isEmpty else { return .failure(ActionError(.noKey)) }
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
    /// "adaptive"; effort low; JSON schema output; no temperature.
    public static func body(mode: ActionMode, text: String, system: String) throws -> Data {
        let label = mode == .in ? "TEXT" : "DRAFT"
        let body: [String: Any] = [
            "model": model(for: mode),
            "max_tokens": 16000,
            "thinking": ["type": mode == .in ? "between_tools" : "adaptive"],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": system,
            "messages": [["role": "user", "content": "MODE: \(mode.rawValue)\n\n\(label):\n\(text)"]],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// HTTP status and body -> result. Thinking blocks are skipped; the answer is the joined text blocks.
    public static func parse(status: Int, body: Data) -> Result<ActionResult, ActionError> {
        guard body.count <= maxResponseBytes else { return .failure(ActionError(.parse)) }
        guard status == 200 else { return .failure(ActionError(kind(status: status, body: body))) }
        guard let resp = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .failure(ActionError(.parse))
        }
        switch resp["stop_reason"] as? String {
        case "refusal": return .failure(ActionError(.refused))
        case "max_tokens": return .failure(ActionError(.truncated))
        default: break
        }
        let blocks = resp["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let obj = jsonObject(in: text),
              let translation = obj["translation"] as? String,
              !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let back = obj["back_translation"] as? String
        else { return .failure(ActionError(.parse)) }
        return .success(ActionResult(translation: translation, backTranslation: back))
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
