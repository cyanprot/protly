import Foundation
import ProtlyCore

/// One Translate/Polish call. Bytes from ProtlyCore, URLSession here.
enum ActionClient {
    /// One session for the process: ephemeral, no cache, no cookies, no redirects (ActionAPI).
    private static let session = URLSession(
        configuration: ActionAPI.sessionConfiguration(), delegate: ActionSessionDelegate(), delegateQueue: nil)

    static func run(_ mode: ActionMode, text: String) async -> Result<ActionResult, ActionError> {
        guard let base = try? ActionAPI.bundledPrompt() else { return .failure(ActionError(.setup)) }
        // The about-me note joins Translate (out) and Polish (fix) only. AboutMe.system leaves Read clipboard (in) as is.
        let note = UserDefaults.standard.string(forKey: AboutMe.defaultsKey) ?? ""
        let system = AboutMe.system(base: base, note: note, mode: mode)
        let req: URLRequest
        switch ActionAPI.request(mode: mode, text: text, system: system, apiKey: Secrets.apiKey) {
        case .success(let r): req = r
        case .failure(let e): return .failure(e)
        }
        do {
            let (bytes, resp) = try await session.bytes(for: req)
            defer { bytes.task.cancel() }  // on every way out: stop the download now, not when it is released
            // Read at most maxResponseBytes: a huge body must not take the keyboard's memory.
            guard let data = try await ActionAPI.collect(bytes) else { return .failure(ActionError(.parse)) }
            return ActionAPI.parse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(ActionError(.timeout))
        } catch {
            return .failure(ActionError(.network))
        }
    }
}
