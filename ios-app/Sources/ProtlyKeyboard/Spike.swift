import Foundation

// Sprint 2 only: one real API call from inside the keyboard.
enum Spike {
    static let workspaceID = "wrkspc_01MYddxiRDrvfHCyhebhtnQj"  // public, same as ios/protly.cherri

    static func ping() async -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(Secrets.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-sonnet-5-5",
            "max_tokens": 20,
            "messages": [["role": "user", "content": "Reply with the single word: pong"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return "HTTP \(code) in \(ms) ms: \(String(decoding: data.prefix(120), as: UTF8.self))"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}
