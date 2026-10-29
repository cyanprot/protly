import Foundation
import ProtlyCore

/// One Translate/Polish call. Bytes from ProtlyCore, URLSession here.
enum ActionClient {
    static func run(_ mode: ActionMode, text: String) async -> Result<ActionResult, ActionError> {
        guard let system = try? ActionAPI.bundledPrompt() else { return .failure(ActionError(.badRequest)) }
        let req: URLRequest
        switch ActionAPI.request(mode: mode, text: text, system: system, apiKey: Secrets.apiKey) {
        case .success(let r): req = r
        case .failure(let e): return .failure(e)
        }
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
