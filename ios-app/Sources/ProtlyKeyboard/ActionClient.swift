import Foundation
import ProtlyCore

/// One Translate/Polish call. Bytes from ProtlyCore, URLSession here.
enum ActionClient {
    static func run(_ mode: ActionMode, text: String) async -> Result<ActionResult, ActionError> {
        guard let system = try? ActionAPI.bundledPrompt(),
              let body = try? ActionAPI.body(mode: mode, text: text, system: system),
              let url = URL(string: ActionAPI.url)
        else { return .failure(ActionError(.badRequest)) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        for (name, value) in ActionAPI.headers(apiKey: Secrets.apiKey) { req.setValue(value, forHTTPHeaderField: name) }
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return ActionAPI.parse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(ActionError(.timeout))
        } catch {
            return .failure(ActionError(.network))
        }
    }
}
