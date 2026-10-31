import Foundation
import XCTest

// The keyboard target needs the iOS SDK, so its rules are checked on its source text here:
// nothing is logged, the clipboard string is read only in readClipboard (a tap), the key goes only
// into ActionAPI.request, and UserDefaults keeps no text but the capped learned words and the about-me note that
// Save on its confirm panel stores (Sprint 7b). Secrets.swift is never opened.
final class KeyboardSourceRulesTests: XCTestCase {
    private func sources() throws -> [(name: String, text: String)] {
        let iosApp = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var out: [(String, String)] = []
        for dir in ["Sources/ProtlyKeyboard", "Sources/Protly"] {
            let url = iosApp.appendingPathComponent(dir)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                // Only a copy of the package outside ios-app/ has no keyboard sources next to it.
                if FileManager.default.fileExists(atPath: iosApp.appendingPathComponent("Package.swift").path) {
                    XCTFail("\(dir) not found")
                    return []
                }
                throw XCTSkip("\(dir) not found next to ProtlyCore")
            }
            for name in names.sorted() where name.hasSuffix(".swift") && name != "Secrets.swift" {
                let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
                out.append((name, Self.withoutComments(text)))
            }
        }
        XCTAssertTrue(out.contains { $0.0 == "KeyboardViewController.swift" })
        return out
    }

    /// Line comments blanked (same length, so line numbers and ranges hold): only code is checked.
    static func withoutComments(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            guard let r = line.range(of: "//") else { return line }
            return String(line[..<r.lowerBound]) + String(repeating: " ", count: line[r.lowerBound...].count)
        }.joined(separator: "\n")
    }

    /// Names bound to an object: `let pb = UIPasteboard.general`, `let d = UserDefaults.standard`.
    private func boundNames(_ object: String, in text: String) -> [String] {
        let ns = text as NSString
        return matches(#"let (\w+) = "# + object, in: text).compactMap { r in
            let re = try! NSRegularExpression(pattern: #"let (\w+) ="#)
            return re.firstMatch(in: text, range: r).map { ns.substring(with: $0.range(at: 1)) }
        }
    }

    private func matches(_ pattern: String, in text: String) -> [NSRange] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    func testNothingIsLogged() throws {
        for (name, text) in try sources() {
            for call in [#"\bprint\("#, #"\bdebugPrint\("#, #"\bdump\("#, #"\bNSLog\b"#, #"\bos_log\b"#, #"\bLogger\("#] {
                // ProtlyHeight logs layout numbers for the phone and CI height checks; see the test below.
                let allowed = name == "ProtlyHeight.swift" && call == #"\bLogger\("# ? 1 : 0
                XCTAssertEqual(matches(call, in: text).count, allowed, "\(name): \(call)")
            }
        }
    }

    func testTheHeightLogCarriesOnlyLayoutValues() throws {
        guard let text = try sources().first(where: { $0.name == "ProtlyHeight.swift" })?.text else { return }
        let ns = text as NSString
        let calls = matches(#"\blog\.(debug|info|notice|error|fault|log)\("#, in: text)
        XCTAssertFalse(calls.isEmpty)
        let values = Set(["reason", "height", "window", "pin", "active"])
        for range in calls {
            let line = lineText(ns, range)
            for m in matches(#"\\\(([A-Za-z_][A-Za-z0-9_.]*)"#, in: line) {
                let name = (line as NSString).substring(with: NSRange(location: m.location + 2, length: m.length - 2))
                XCTAssertTrue(values.contains(name), "ProtlyHeight logs \(name): \(line)")
            }
        }
    }

    func testTheKeyGoesOnlyIntoTheRequest() throws {
        var uses: [String] = []
        for (name, text) in try sources() {
            let ns = text as NSString
            uses += matches(#"Secrets\.\w+"#, in: text).map { "\(name): \(lineText(ns, $0))" }
        }
        XCTAssertEqual(uses.count, 1, uses.joined(separator: "\n"))
        XCTAssertTrue(uses.first?.hasPrefix("ActionClient.swift:") == true, uses.joined())
        XCTAssertTrue(uses.first?.contains("ActionAPI.request(") == true && uses.first?.contains("apiKey: Secrets.apiKey") == true,
                      uses.joined())
    }

    /// keyboard-ui 003: the one write, Copy on the result card, is an assignment inside copyResult().
    func testTheClipboardStringIsReadOnlyInReadClipboard() throws {
        var writes: [String] = []
        for (name, text) in try sources() {
            let ns = text as NSString
            let names = Set(boundNames(#"UIPasteboard\.general\b"#, in: text))
            let readers = [#"UIPasteboard\.general\.(string|strings|items|data|value)\b"#]
                + names.map { #"\b\#($0)\.(string|strings|items|data|value)\b"# }
            let uses = readers.flatMap { matches($0, in: text) }
            guard !uses.isEmpty else { continue }
            XCTAssertEqual(name, "KeyboardViewController.swift")
            guard let read = body(of: "private func readClipboard()", in: ns) else {
                XCTFail("\(name): readClipboard not found"); continue
            }
            let copy = body(of: "func copyResult()", in: ns)
            for r in uses {
                let rest = ns.substring(from: r.location + r.length)
                if rest.range(of: #"^\s*=(?!=)"#, options: .regularExpression) != nil {
                    XCTAssertTrue(copy.map { NSLocationInRange(r.location, $0) } == true,
                                  "\(name): clipboard write outside copyResult: \(lineText(ns, r))")
                    writes.append("\(name): \(lineText(ns, r))")
                } else {
                    XCTAssertTrue(NSLocationInRange(r.location, read),
                                  "\(name): clipboard read outside readClipboard: \(lineText(ns, r))")
                }
            }
        }
        XCTAssertEqual(writes.count, 1, writes.joined(separator: "\n"))
    }

    /// The range of a function's body: from its declaration to the first line that is only `    }`.
    private func body(of declaration: String, in ns: NSString) -> NSRange? {
        let start = ns.range(of: declaration)
        guard start.location != NSNotFound else { return nil }
        let end = ns.range(of: "\n    }\n", range: NSRange(location: start.location, length: ns.length - start.location))
        guard end.location != NSNotFound else { return nil }
        return NSRange(location: start.location, length: end.location - start.location)
    }

    func testUserDefaultsHoldsOnlyTheChangeCountTheLanguageTheLearnedWordsAndTheNote() throws {
        var noteSaves: [String] = []
        var appStorage: [String] = []
        for (name, text) in try sources() {
            let ns = text as NSString
            let receivers = [#"UserDefaults\.standard"#, #"UserDefaults\([^)]*\)"#]
                + boundNames(#"UserDefaults\b"#, in: text).map { #"\b\#($0)"# }
            for receiver in receivers {
                // \s* catches a write chained onto the next line.
                for r in matches(receiver + #"\s*\.(set|setValue)\("#, in: text) {
                    let line = lineText(ns, r)
                    // The about-me note (at most AboutMe.cap scalars), saved only by Save on its confirm panel,
                    // because any app can put the marker on the clipboard.
                    if line.contains("forKey: AboutMe.defaultsKey)") {
                        let above = ns.substring(to: ns.lineRange(for: r).location)
                            .components(separatedBy: "\n").dropLast().last ?? ""
                        XCTAssertTrue(above.contains("case let .confirmNote(") && above.contains("AboutMe.canSave("),
                                      "\(name): note saved off the confirm panel or without the Save delay: \(line)")
                        let insert = body(of: "func insertResult()", in: ns)
                        XCTAssertTrue(insert.map { NSLocationInRange(r.location, $0) } == true,
                                      "\(name): note saved outside insertResult: \(line)")
                        noteSaves.append("\(name): \(line)")
                        continue
                    }
                    // The one store of typed text: Words.swift saves the learned words, which stay bounded
                    // (LearnedWords: at most 1,000 per language, keys of at most 32 characters).
                    let learned = name == "Words.swift" && line.contains("forKey: Self.learnedKey")
                    XCTAssertTrue(line.contains("changeCount") || line.contains("previousKey") || learned,
                                  "\(name): \(line)")
                }
            }
            // No other way into the defaults or the preferences.
            for call in [#"\bsetPersistentDomain\b"#, #"\bremovePersistentDomain\b"#, #"\bsetVolatileDomain\b"#,
                         #"\bCFPreferencesSet\w*"#, #"@SceneStorage"#] {
                XCTAssertEqual(matches(call, in: text).count, 0, "\(name): \(call)")
            }
            // The container app keeps the note the user types there, under that key and no other.
            for r in matches(#"@AppStorage"#, in: text) {
                XCTAssertTrue(name == "ProtlyApp.swift" && lineText(ns, r).contains("@AppStorage(AboutMeLink.defaultsKey)"),
                              "\(name): \(lineText(ns, r))")
                appStorage.append("\(name): \(lineText(ns, r))")
            }
        }
        XCTAssertEqual(noteSaves.count, 1, noteSaves.joined(separator: "\n"))
        XCTAssertTrue(noteSaves.first?.hasPrefix("KeyboardViewController.swift:") == true, noteSaves.joined())
        XCTAssertEqual(appStorage.count, 1, appStorage.joined(separator: "\n"))
    }

    /// Save is the panel's insert button: insertResult has one caller, that closure.
    func testInsertResultIsCalledOnlyByThePanelsInsertButton() throws {
        var calls: [String] = []
        for (name, text) in try sources() {
            let ns = text as NSString
            calls += matches(#"\binsertResult\("#, in: text)
                .filter { !ns.substring(to: $0.location).hasSuffix("func ") }
                .map { "\(name): \(lineText(ns, $0))" }
        }
        XCTAssertEqual(calls.count, 1, calls.joined(separator: "\n"))
        XCTAssertTrue(calls.first?.hasPrefix("KeyboardViewController.swift:") == true, calls.joined())
        XCTAssertTrue(calls.first?.contains("insert: { [unowned host] in host.insertResult() }") == true, calls.joined())
    }

    /// typing-fixes 001: the word being typed is plain text. Marked text made hosts hide the word on dark screens,
    /// drop it on Return in web views and hold back the edit menu (docs/research/2026-10-30-*.md).
    func testNoMarkedTextInTheKeyboard() throws {
        for (name, text) in try sources() {
            let ns = text as NSString
            for call in [#"\bsetMarkedText\b"#, #"\bunmarkText\b"#, #"\bmarkedText\w*"#] {
                for r in matches(call, in: text) {
                    XCTFail("\(name): marked text: \(lineText(ns, r))")
                }
            }
        }
    }

    /// Host callbacks only read the field and decide; they never write to it (edit-menu-missing.md 4.2). A write
    /// there would land wherever the user just put the cursor or selection. Checked: the callbacks and every
    /// function they call on the way (refreshMode, refreshWords, savePrevious ...), in whichever file it lives.
    func testHostCallbacksNeverWrite() throws {
        let files = try sources().map { (name: $0.name, ns: $0.text as NSString) }
        let writes = [#"\binsertText\b"#, #"\bdeleteBackward\b"#, #"\badjustTextPosition\b"#, #"\bsetMarkedText\b"#,
                      #"\bunmarkText\b"#, #"\bapply\("#, #"\bcommitWord\("#, #"\bFieldText\.replace\b"#,
                      // The typing and action entry points all write.
                      #"\btypeLetter\("#, #"\bbackspaceInWord\("#, #"\bflipWord\("#, #"\bpickSuggestion\("#,
                      #"\bact\("#, #"\binsertResult\("#, #"\bundoInsert\("#]
        let required = ["override func textDidChange(", "override func selectionDidChange(", "func refreshField()",
                        "func noticeFieldMoved()", "func abandonWord()", "func refreshMode()", "func refreshWords()",
                        "func savePrevious()", "func observed()"]
        // Callbacks Protly may override later fall under the same rule.
        let optional = ["override func selectionWillChange(", "override func textWillChange(",
                        "override func textDidChangeAsync("]
        for declaration in required + optional {
            var found: (name: String, body: NSString)?
            for f in files {
                if let range = body(of: declaration, in: f.ns) {
                    found = (f.name, f.ns.substring(with: range) as NSString)
                    break
                }
            }
            guard let found else {
                if required.contains(declaration) { XCTFail("\(declaration) not found in the keyboard sources") }
                continue
            }
            for write in writes {
                for r in matches(write, in: found.body as String) {
                    XCTFail("\(found.name): \(declaration) writes: \(lineText(found.body, r))")
                }
            }
        }
    }

    /// typing-fixes 003: the space bar trackpad is Protly's own (SpaceTrackpad in ProtlyCore). Every move goes
    /// through the controller's adjustTextPosition override, which forgets the field model (FieldWatch); a finger
    /// drifting up or down never drops a move (R1); only space gets the shorter hold (R3); haptics stay off (R2 is
    /// out of scope).
    func testSpaceTrackpadWiring() throws {
        let all = try sources()
        guard let handler = all.first(where: { $0.name == "ProtlyActionHandler.swift" })?.text,
              let controller = all.first(where: { $0.name == "KeyboardViewController.swift" })?.text else {
            return XCTFail("ProtlyActionHandler.swift or KeyboardViewController.swift not found")
        }
        let hns = handler as NSString
        guard let drag = body(of: "override func handleDrag(", in: hns).map({ hns.substring(with: $0) }) else {
            return XCTFail("ProtlyActionHandler does not override handleDrag")
        }
        for (needle, why) in [
            ("guard action == .space else", "only space takes the trackpad path"),
            ("keyboardContext.isSpaceDragGestureActive", "nothing may move before the hold starts the trackpad"),
            ("host.beginSpaceDrag()", "the first event must commit the word and take the snapshot"),
            ("drag.move(startX: Double(startLocation.x), startY: Double(startLocation.y)",
             "the space drag does not go through SpaceDrag with the touch's start (a new touch must reset it)"),
            ("host.adjustTextPosition(by: offset)", "the drag does not move through the controller's override"),
        ] {
            XCTAssertTrue(drag.contains(needle), "handleDrag: \(why) (\(needle))")
        }
        // A new press or the end of a drag drops the trackpad: otherwise the next drag would start from the last
        // drag's finger position and jump. A cancelled touch sends neither: SpaceDrag resets on a new start location.
        XCTAssertEqual(matches(#"gesture == \.press \|\| gesture == \.release \|\| gesture == \.end\s*\{\s*drag\.reset\(\)"#,
                               in: handler).count, 1, "the trackpad is not reset on press, release and end")
        XCTAssertFalse(handler.contains("SpaceTrackpad?"), "the handler keeps its own trackpad instead of SpaceDrag")
        XCTAssertFalse(handler.contains("textDocumentProxy"), "ProtlyActionHandler touches the proxy itself")
        // The snapshot reads the field before the commit (a read after it may not show it yet) and ends the flip
        // and Undo, as any cursor move does.
        let cns = controller as NSString
        if let begin = body(of: "func beginSpaceDrag()", in: cns).map({ cns.substring(with: $0) }) {
            let read = (begin as NSString).range(of: "documentContextBeforeInput")
            let commit = (begin as NSString).range(of: "commitWord()")
            XCTAssertTrue(read.location != NSNotFound && commit.location != NSNotFound && read.location < commit.location,
                          "beginSpaceDrag must read the context before it commits the word")
            XCTAssertTrue(begin.contains("session.forgetLast()") && begin.contains("endUndo()"),
                          "beginSpaceDrag must end the flip and Undo")
        } else {
            XCTFail("KeyboardViewController.beginSpaceDrag not found")
        }
        // Only FieldText's whole-field read moves the cursor on the proxy directly (act() forgets the model after).
        for (name, text) in all where name != "FieldText.swift" {
            let ns = text as NSString
            for r in matches(#"\badjustTextPosition\(byCharacterOffset"#, in: text) {
                XCTFail("\(name): cursor move outside the controller's override: \(lineText(ns, r))")
            }
        }
        XCTAssertEqual(matches(#"spaceDragGestureHandler\.verticalThreshold\s*=\s*\.greatestFiniteMagnitude"#,
                               in: controller).count, 1, "R1: KeyboardKit's vertical threshold is not lifted")
        let delays = matches(#"\blongPressDelay:"#, in: controller)
        XCTAssertEqual(delays.count, 1, "one long-press delay, for space only")
        XCTAssertEqual(matches(#"action == \.space\s*\?\s*\.init\(longPressDelay:\s*SpaceTrackpad\.longPressDelay\)\s*:\s*\.standard\b"#,
                               in: controller).count, 1, "R3: the shorter hold is not limited to space")
        XCTAssertTrue(controller.contains("hapticConfiguration = .disabled"), "haptics must stay off")
    }

    /// keyboard-ui 001: the bar and the protly key read their labels only through BarAction (ProtlyCore), so a label
    /// cannot drift from the request again. Longer strings (the Full Access notice, the panel's "Polishing") stay
    /// allowed; the container app has its own copy. The pill's motion has a Reduce Motion form.
    func testBarLabelsComeOnlyFromBarAction() throws {
        let all = try sources()
        for (name, text) in all where name != "ProtlyApp.swift" {
            let ns = text as NSString
            for r in matches(#""(Translate|Polish|Read clipboard)""#, in: text) {
                XCTFail("\(name): a bar label outside BarAction: \(lineText(ns, r))")
            }
        }
        guard let bar = all.first(where: { $0.name == "ProtlyBar.swift" })?.text else {
            return XCTFail("ProtlyBar.swift not found")
        }
        XCTAssertTrue(bar.contains("accessibilityReduceMotion"), "ProtlyBar.swift has no Reduce Motion form")
    }

    /// keyboard-ui 003: ActionClient stays nonisolated, so the download and the parsing run off the main actor, and
    /// it reads the reply only through ProtlyCore's stream driver.
    func testActionClientIsNotOnTheMainActor() throws {
        guard let client = try sources().first(where: { $0.name == "ActionClient.swift" })?.text else {
            return XCTFail("ActionClient.swift not found")
        }
        XCTAssertFalse(client.contains("@MainActor"), "ActionClient.swift must not be on the main actor")
        XCTAssertTrue(client.contains("ActionAPI.updates"), "ActionClient.swift must read the reply through ActionAPI.updates")
    }

    private func lineText(_ ns: NSString, _ r: NSRange) -> String {
        let line = ns.lineRange(for: r)
        return "\(ns.substring(to: r.location).components(separatedBy: "\n").count): "
            + ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
