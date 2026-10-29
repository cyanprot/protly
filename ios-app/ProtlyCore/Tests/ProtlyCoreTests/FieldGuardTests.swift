import Foundation
import XCTest
@testable import ProtlyCore

// Insert deletes `original.count` characters and Undo `inserted.count`: both run only while the field
// still ends with exactly that text, so an edit anywhere in it while the request ran stops them.
final class FieldGuardTests: XCTestCase {
    let draft = "First line of a long draft that the user wrote. " + String(repeating: "Then more text. ", count: 10)

    func testInsertWhenTheFieldIsAsRead() {
        XCTAssertTrue(FieldGuard.canReplace(draft, before: draft, after: ""))
        XCTAssertTrue(FieldGuard.canReplace("안녕 👨‍👩‍👧", before: "안녕 👨‍👩‍👧", after: ""))
    }

    func testNoInsertAfterAnEditFarFromTheEnd() {
        // The user pasted near the start, then put the cursor back at the end: the last 40 characters match.
        let edited = "Fi" + "XYZ" + draft.dropFirst(2)
        XCTAssertEqual(String(edited.suffix(40)), String(draft.suffix(40)))
        XCTAssertFalse(FieldGuard.canReplace(draft, before: edited, after: ""))
        // A cut near the start: the field is shorter than what Insert would delete.
        XCTAssertFalse(FieldGuard.canReplace(draft, before: String(draft.dropFirst(6)), after: ""))
    }

    func testNoInsertWithTextAfterTheCursorOrNothingRead() {
        XCTAssertFalse(FieldGuard.canReplace(draft, before: draft, after: " tail"))
        XCTAssertFalse(FieldGuard.canReplace("", before: draft, after: ""))
    }

    func testUndoOnlyWhileTheInsertIsIntact() {
        let inserted = "Polished text that protly inserted, long enough to pass forty characters."
        XCTAssertTrue(FieldGuard.canUndo(inserted, before: "Earlier text. " + inserted))
        let cut = inserted.replacingOccurrences(of: "Polished ", with: "")
        XCTAssertEqual(String(cut.suffix(40)), String(inserted.suffix(40)))
        XCTAssertFalse(FieldGuard.canUndo(inserted, before: "Earlier text. " + cut))
        XCTAssertFalse(FieldGuard.canUndo("", before: "x"))
    }

    func testCharacterBoundariesDecide() {
        // An insert that joined the character before it is not intact: its delete count would take that
        // character too. Swift's hasSuffix compares whole characters; a UTF-16 or scalar compare would not.
        XCTAssertFalse(FieldGuard.canUndo("\u{301}abc", before: "xe\u{301}abc"))
        XCTAssertFalse(FieldGuard.canUndo("\u{11A8}bc", before: "가\u{11A8}bc"))
        XCTAssertFalse(FieldGuard.canUndo("🇷ab", before: "🇰🇷ab"))
        XCTAssertFalse(FieldGuard.canUndo("\u{200D}👦", before: "👨\u{200D}👦"))
        XCTAssertFalse(FieldGuard.canUndo("\n", before: "a\r\n"))  // "\r\n" is one character
        XCTAssertFalse(FieldGuard.canUndo("a\r", before: "a\r\n"))
        // Canonically equal text is the same text, with the same character count.
        let nfc = "안녕", nfd = "안녕".decomposedStringWithCanonicalMapping
        XCTAssertTrue(FieldGuard.canReplace(nfc, before: nfd, after: ""))
        XCTAssertEqual(nfc.count, nfd.count)
        XCTAssertTrue(FieldGuard.canUndo("\u{00C5}", before: "x\u{212B}"))
    }
}
