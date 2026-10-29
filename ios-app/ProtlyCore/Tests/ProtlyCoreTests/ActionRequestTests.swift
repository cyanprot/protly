import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ProtlyCore

// The request the keyboard sends: what goes where, and what is refused before anything is sent.
final class ActionRequestTests: XCTestCase {
    private func request(_ text: String, mode: ActionMode = .fix, key: String = "k") -> Result<URLRequest, ActionError> {
        ActionAPI.request(mode: mode, text: text, system: "S", apiKey: key)
    }

    private func kind(_ r: Result<URLRequest, ActionError>) -> ActionError.Kind? {
        if case .failure(let e) = r { return e.kind }
        return nil
    }

    func testTextOverTheLimitIsRefusedBeforeAnyRequest() throws {
        let max = String(repeating: "a", count: ActionAPI.maxInputLength)
        XCTAssertNotNil(try request(max).get().httpBody)
        XCTAssertEqual(kind(request(max + "a")), .tooLong)
        // The limit is in UTF-16 units, the unit the field and the pasteboard measure in: an emoji is two.
        let emoji = String(repeating: "😀", count: ActionAPI.maxInputLength / 2)
        XCTAssertNotNil(try request(emoji).get().httpBody)
        XCTAssertEqual(kind(request(emoji + "a")), .tooLong)
        // A multi-megabyte clipboard is refused cheaply, without building a body.
        XCTAssertEqual(kind(request(String(repeating: "가", count: 5_000_000), mode: .in)), .tooLong)
        XCTAssertFalse(ActionError(.tooLong).message.isEmpty)
    }

    func testNothingIsKeptOnDisk() throws {
        // Field text, clipboard text and the reply live only in memory: no URL cache, no cookie store.
        let req = try request("hi").get()
        XCTAssertEqual(req.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(req.httpShouldHandleCookies)
        let c = ActionAPI.sessionConfiguration()
        XCTAssertNil(c.urlCache)
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertFalse(c.httpShouldSetCookies)
        XCTAssertNil(c.urlCredentialStorage)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testARequestEndsInBoundedTimeAndSize() throws {
        // 30 s without a byte fails, as before; a reply dribbled byte by byte also ends, at 90 s in all.
        XCTAssertEqual(try request("hi").get().timeoutInterval, 30)
        let c = ActionAPI.sessionConfiguration()
        XCTAssertEqual(c.timeoutIntervalForRequest, 30)
        XCTAssertEqual(c.timeoutIntervalForResource, 90)
        // A 16000-token reply is far below the cap; a bigger body is not parsed at all.
        XCTAssertGreaterThanOrEqual(ActionAPI.maxResponseBytes, 1_000_000)
        let ok = #"{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"translation\":\"Hi\",\"back_translation\":\"\"}"}]}"#
        let padded = String(ok.dropLast()) + #","pad":""# + String(repeating: "x", count: ActionAPI.maxResponseBytes) + #""}"#
        XCTAssertEqual(try ActionAPI.parse(status: 200, body: Data(ok.utf8)).get().translation, "Hi")
        guard case .failure(let e) = ActionAPI.parse(status: 200, body: Data(padded.utf8)) else { return XCTFail("parsed") }
        XCTAssertEqual(e.kind, .parse)
    }
}
