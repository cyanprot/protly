import XCTest
@testable import ProtlyCore

final class KeyEncoderTests: XCTestCase {
    func testHangulKeys() {
        XCTAssertEqual(KeyEncoder.keys(forHangul: "안녕").map(Dubeolsik.koreanKeyString), "dkssud")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "했어").map(Dubeolsik.koreanKeyString), "goTdj")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "읽어").map(Dubeolsik.koreanKeyString), "dlfrdj")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "ㅋㅋ").map(Dubeolsik.koreanKeyString), "zz")
        XCTAssertNil(KeyEncoder.keys(forHangul: "TV를"))
    }

    func testLatinKeys() {
        let k = KeyEncoder.keys(forLatin: "The", sentenceStart: true)!
        XCTAssertEqual(k.first?.shift, .automatic)
        let n = KeyEncoder.keys(forLatin: "NYC", sentenceStart: false)!
        XCTAssertEqual(n.map(\.shift), [.manual, .manual, .manual])
        XCTAssertNil(KeyEncoder.keys(forLatin: "don't", sentenceStart: false))
    }
}
