import Foundation
import ProtlyCore

/// One Translate/Polish call. Bytes from ProtlyCore, URLSession here.
enum ActionClient {
    /// One session for the process: ephemeral, no cache, no cookies, no redirects (ActionAPI).
    private static let session = URLSession(
        configuration: ActionAPI.sessionConfiguration(), delegate: ActionSessionDelegate(), delegateQueue: nil)

    static func run(_ mode: ActionMode, text: String) async -> Result<ActionResult, ActionError> {
        guard let system = try? ActionAPI.bundledPrompt() else { return .failure(ActionError(.setup)) }
        let req: URLRequest
        switch ActionAPI.request(mode: mode, text: text, system: system, apiKey: Secrets.apiKey) {
        case .success(let r): req = r
        case .failure(let e): return .failure(e)
        }
        do {
            let (bytes, resp) = try await session.bytes(for: req)
            // Read at most maxResponseBytes: a huge body must not take the keyboard's memory.
            var data = Data()
            for try await byte in bytes {
                guard data.count < ActionAPI.maxResponseBytes else {
                    bytes.task.cancel()  // stop the download now, not when the sequence is released
                    return .failure(ActionError(.parse))
                }
                data.append(byte)
            }
            return ActionAPI.parse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(ActionError(.timeout))
        } catch {
            return .failure(ActionError(.network))
        }
    }
}
