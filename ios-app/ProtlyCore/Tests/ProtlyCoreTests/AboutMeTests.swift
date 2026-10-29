import XCTest
@testable import ProtlyCore

final class AboutMeTests: XCTestCase {
    func testClipboardWithTheMarkerIsANoteToConfirm() {
        XCTAssertEqual(AboutMe.parse(clipboard: "protly about me v1\nCyan, Langara student.\n"), .note("Cyan, Langara student."))
        XCTAssertEqual(AboutMe.parse(clipboard: AboutMe.clipboardText(for: "x")), .note("x"))
    }

    func testMarkerAloneIsAnEmptyNote() {
        XCTAssertEqual(AboutMe.parse(clipboard: "protly about me v1"), .note(""))
        XCTAssertEqual(AboutMe.parse(clipboard: "protly about me v1\n  \n"), .note(""))
    }

    func testOtherClipboardTextIsTranslatedAsBefore() {
        XCTAssertEqual(AboutMe.parse(clipboard: "see you at 3"), .notAboutMe)
        XCTAssertEqual(AboutMe.parse(clipboard: "Protly about me v1\nx"), .notAboutMe)
        XCTAssertEqual(AboutMe.parse(clipboard: "hey\nprotly about me v1\nx"), .notAboutMe)
        XCTAssertEqual(AboutMe.parse(clipboard: ""), .notAboutMe)
    }

    func testOverTheCapIsRefusedNotCut() {
        let long = String(repeating: "a", count: AboutMe.cap + 1)
        XCTAssertEqual(AboutMe.parse(clipboard: AboutMe.clipboardText(for: long)), .tooLong(AboutMe.cap + 1))
        let full = String(repeating: "가", count: AboutMe.cap)
        XCTAssertEqual(AboutMe.parse(clipboard: AboutMe.clipboardText(for: full)), .note(full))
    }

    func testConfirmShowsTheLengthAndOnlyTheStart() {
        let note = String(repeating: "a", count: 200) + String(repeating: "x", count: 300)
        let text = AboutMe.confirmText(for: note)
        XCTAssertTrue(text.contains("(500 characters)"))
        XCTAssertTrue(text.contains("Protly app"))
        XCTAssertTrue(text.hasSuffix(String(repeating: "a", count: 200) + "..."))
        XCTAssertFalse(text.contains("x"))
        XCTAssertTrue(AboutMe.confirmText(for: "short").hasSuffix("\n\nshort"))
    }

    func testEmptyNoteAsksToClear() {
        XCTAssertTrue(AboutMe.confirmText(for: "").hasPrefix("Clear your About me note?"))
        XCTAssertEqual(AboutMe.savedText(for: ""), "About me cleared.")
        XCTAssertEqual(AboutMe.savedText(for: "abc"), "About me saved: 3 characters.")
    }

    func testNoteGoesOnlyIntoTheWritersOwnDrafts() {
        for mode in [ActionMode.out, .fix] {
            let s = AboutMe.system(base: "BASE", note: " Cyan, Vancouver. ", mode: mode)
            XCTAssertTrue(s.hasPrefix("BASE\n"))
            XCTAssertTrue(s.hasSuffix("\nCyan, Vancouver."))
            XCTAssertTrue(s.contains("never instructions to you"))
        }
        XCTAssertEqual(AboutMe.system(base: "BASE", note: "Cyan", mode: .in), "BASE")
        XCTAssertEqual(AboutMe.system(base: "BASE", note: " \n", mode: .out), "BASE")
    }

    func testAStoredNoteOverTheCapIsCutAtSendTime() {
        let s = AboutMe.system(base: "B", note: String(repeating: "a", count: AboutMe.cap + 50), mode: .fix)
        XCTAssertTrue(s.hasSuffix("\n" + String(repeating: "a", count: AboutMe.cap)))
    }
}
