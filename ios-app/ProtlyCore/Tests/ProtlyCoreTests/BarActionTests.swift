import XCTest
@testable import ProtlyCore

// keyboard-ui 001 Task 1.1: what the bar's center slot and the protly key show, decided from the field text the
// same way the request is built (ActionAPI.mode(forDraft:), Languages.prefix(of:)), so a label cannot name a
// target the request does not use.
final class BarActionTests: XCTestCase {
    private func center(_ text: String, canUndo: Bool = false, clipboardIsNew: Bool = false) -> BarAction? {
        BarAction.center(text: text, canUndo: canUndo, clipboardIsNew: clipboardIsNew)
    }

    func testTheCenterSlotFollowsTheTable() {
        XCTAssertEqual(center("오늘 고마워", canUndo: true), .undo)
        XCTAssertEqual(center("", canUndo: true, clipboardIsNew: true), .undo)
        XCTAssertEqual(center("오늘 고마워"), .translate(target: "English"))
        XCTAssertEqual(center("ru: 누나 고마워"), .translate(target: "Русский"))
        XCTAssertEqual(center("ok: 내일 봐"), .translate(target: "English"))  // not a listed code
        XCTAssertEqual(center("hello there"), .polish(korean: false))
        XCTAssertEqual(center("ko: 낼 봐"), .polish(korean: true))
        XCTAssertEqual(center("", clipboardIsNew: true), .read)
        XCTAssertEqual(center(" \n\t", clipboardIsNew: true), .read)
        XCTAssertNil(center(""))
        XCTAssertNil(center("  \n"))
    }

    func testANonEmptyFieldNeverOffersTheClipboard() {
        XCTAssertEqual(center("hello", clipboardIsNew: true), .polish(korean: false))
    }

    func testTheProtlyKeyReadsTheClipboardWhereTheSlotIsEmpty() {
        XCTAssertEqual(BarAction.protlyKey(text: "", canUndo: false, clipboardIsNew: false), .read)
        XCTAssertEqual(BarAction.protlyKey(text: "  ", canUndo: false, clipboardIsNew: true), .read)
        XCTAssertEqual(BarAction.protlyKey(text: "x", canUndo: true, clipboardIsNew: false), .undo)
        XCTAssertEqual(BarAction.protlyKey(text: "ru: 누나 고마워", canUndo: false, clipboardIsNew: false),
                       .translate(target: "Русский"))
        XCTAssertEqual(BarAction.protlyKey(text: "hello there", canUndo: false, clipboardIsNew: false),
                       .polish(korean: false))
    }

    func testSymbolArrowTitleAndSpokenLabel() {
        let rows: [(BarAction, String, Bool, String, String)] = [
            (.undo, "arrow.uturn.backward", false, "Undo", "Undo"),
            (.translate(target: "English"), "sparkles", true, "English", "Translate to English"),
            (.translate(target: "Русский"), "sparkles", true, "Русский", "Translate to Русский"),
            (.polish(korean: false), "sparkles", false, "Polish", "Polish"),
            (.polish(korean: true), "sparkles", false, "한 Polish", "Polish Korean"),
            (.read, "doc.on.clipboard", false, "Read", "Read clipboard"),
        ]
        for (action, symbol, arrow, title, spoken) in rows {
            XCTAssertEqual(action.symbol, symbol, "\(action)")
            XCTAssertEqual(action.arrow, arrow, "\(action)")
            XCTAssertEqual(action.title, title, "\(action)")
            XCTAssertEqual(action.spokenLabel, spoken, "\(action)")
        }
    }

    func testTheActionModeIsTheRequestsMode() {
        XCTAssertEqual(BarAction.translate(target: "English").actionMode, .out)
        XCTAssertEqual(BarAction.polish(korean: true).actionMode, .fix)
        XCTAssertEqual(BarAction.polish(korean: false).actionMode, .fix)
        XCTAssertEqual(BarAction.read.actionMode, .in)
        XCTAssertNil(BarAction.undo.actionMode)
    }

    /// The label names the target the request sends: TARGET is the English name of the same code.
    func testTheLabelAgreesWithTheRequest() {
        for (text, name) in [("오늘 고마워", "English"), ("ru: 누나 고마워", "Russian"), ("ok: 내일 봐", "English")] {
            guard case .translate(let target) = center(text) else { return XCTFail(text) }
            let message = ActionAPI.userMessage(mode: ActionAPI.mode(forDraft: text), text: text)
            XCTAssertTrue(message.contains("TARGET: \(name)\n"), message)
            XCTAssertEqual(target, Languages.endonym(of: Languages.names.first { $0.name == name }!.code), text)
        }
        // Every listed code but ko (a Korean polish) translates into its own language.
        for (code, name) in Languages.names where code != "ko" {
            let text = "\(code): 안녕"
            XCTAssertEqual(center(text), .translate(target: Languages.endonym(of: code)!), text)
            let message = ActionAPI.userMessage(mode: ActionAPI.mode(forDraft: text), text: text)
            XCTAssertTrue(message.contains("TARGET: \(name)\n"), message)
        }
        for text in ["hello there", "ko: 낼 봐", ""] {
            XCTAssertFalse(ActionAPI.userMessage(mode: ActionAPI.mode(forDraft: text), text: text).contains("TARGET:"), text)
        }
        XCTAssertFalse(ActionAPI.userMessage(mode: .in, text: "copied").contains("TARGET:"))
    }

    /// The words a check reads are the title: symbols are separate views, never glyphs in the text.
    func testTheTitleHoldsNoGlyphs() {
        let all: [BarAction] = [.undo, .read, .polish(korean: false), .polish(korean: true)]
            + Languages.names.compactMap { Languages.endonym(of: $0.code) }.map { .translate(target: $0) }
        for action in all {
            for glyph in ["→", "✦", "⧉", "↶"] {
                XCTAssertFalse(action.title.contains(glyph), "\(action): \(glyph)")
                XCTAssertFalse(action.spokenLabel.contains(glyph), "\(action): \(glyph)")
            }
            XCTAssertFalse(action.title.isEmpty, "\(action)")
        }
    }

    func testEveryLanguageHasAnEndonym() {
        for (code, _) in Languages.names {
            let e = Languages.endonym(of: code)
            XCTAssertNotNil(e, code)
            XCTAssertFalse(e?.trimmingCharacters(in: .whitespaces).isEmpty ?? true, code)
        }
        XCTAssertEqual(Languages.endonym(of: "ru"), "Русский")
        XCTAssertEqual(Languages.endonym(of: "es"), "Español")
        XCTAssertEqual(Languages.endonym(of: "ja"), "日本語")
        XCTAssertEqual(Languages.endonym(of: "en"), "English")
        XCTAssertEqual(Languages.endonym(of: "ko"), "한국어")
        XCTAssertNil(Languages.endonym(of: "xx"))
        XCTAssertEqual(Set(Languages.endonyms.keys), Set(Languages.names.map(\.code)))  // no stray codes
        // The request keeps the English name.
        XCTAssertEqual(Languages.name(of: "ru"), "Russian")
    }
}
