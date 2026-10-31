import Foundation
import ProtlyCore

/// One Translate/Polish/Read call, streamed. The request and the reading of the reply are ProtlyCore's
/// (ActionAPI.request, ActionAPI.updates); URLSession is here. Never on the main actor: the download and the parsing
/// run off it, and only the consumer hops back.
enum ActionClient {
    /// One session for the process: ephemeral, no cache, no cookies, no redirects (ActionAPI).
    private static let session = URLSession(
        configuration: ActionAPI.sessionConfiguration(), delegate: ActionSessionDelegate(), delegateQueue: nil)

    /// Partial translations, then exactly one done or failed. Ending the consumer (its task cancelled) cancels the
    /// download; a cancel ends the stream with nothing more.
    static func run(_ mode: ActionMode, text: String) -> AsyncStream<ActionUpdate> {
        guard let base = try? ActionAPI.bundledPrompt() else { return failed(ActionError(.setup)) }
        // The about-me note joins Translate (out) and Polish (fix) only. AboutMe.system leaves Read clipboard (in) as is.
        let note = UserDefaults.standard.string(forKey: AboutMe.defaultsKey) ?? ""
        let system = AboutMe.system(base: base, note: note, mode: mode)
        let req: URLRequest
        switch ActionAPI.request(mode: mode, text: text, system: system, apiKey: Secrets.apiKey) {
        case .success(let r): req = r
        case .failure(let e): return failed(e)
        }
        return ActionAPI.updates { () async throws -> (status: Int, bytes: URLSession.AsyncBytes, stop: @Sendable () -> Void) in
            let (bytes, response) = try await session.bytes(for: req)
            let task = bytes.task
            // The timeouts stay URLSession's (ActionAPI.sessionConfiguration): both cancel this read.
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, bytes, { task.cancel() })
        }
    }

    private static func failed(_ error: ActionError) -> AsyncStream<ActionUpdate> {
        AsyncStream { continuation in
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }
}
