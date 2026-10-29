import XCTest
@testable import ProtlyCore

final class KeycapTests: XCTestCase {
    func testKeycapsMapBackToKeys() {
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "a"), "a")
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "Q"), "q")
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "ㅂ"), "q")
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "ㅃ"), "q")
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "ㅖ"), "p")
        XCTAssertEqual(Dubeolsik.letter(forKeycap: "ㅡ"), "m")
        XCTAssertNil(Dubeolsik.letter(forKeycap: "é"))
        XCTAssertNil(Dubeolsik.letter(forKeycap: "1"))
        XCTAssertNil(Dubeolsik.letter(forKeycap: ""))
        XCTAssertNil(Dubeolsik.letter(forKeycap: "ab"))
        // Every keycap the layouts show maps back to its key.
        for (key, jamo) in Dubeolsik.plain { XCTAssertEqual(Dubeolsik.letter(forKeycap: String(jamo)), key) }
        for (key, jamo) in Dubeolsik.shifted { XCTAssertEqual(Dubeolsik.letter(forKeycap: String(jamo)), key) }
        for key in "abcdefghijklmnopqrstuvwxyz" {
            XCTAssertEqual(Dubeolsik.letter(forKeycap: String(key)), key)
            XCTAssertEqual(Dubeolsik.letter(forKeycap: key.uppercased()), key)
        }
    }
}
