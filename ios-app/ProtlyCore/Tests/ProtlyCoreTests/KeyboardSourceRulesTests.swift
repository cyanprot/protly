import Foundation
import XCTest

// The keyboard target needs the iOS SDK, so its rules are checked on its source text here:
// nothing is logged, the clipboard string is read only in readClipboard (a tap), the key goes only
// into ActionAPI.request, and UserDefaults keeps no text. Secrets.swift is never opened.
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
                XCTAssertEqual(matches(call, in: text).count, 0, "\(name): \(call)")
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

    func testTheClipboardStringIsReadOnlyInReadClipboard() throws {
        for (name, text) in try sources() {
            let ns = text as NSString
            let names = boundNames(#"UIPasteboard\.general\b"#, in: text)
            let readers = [#"UIPasteboard\.general\.(string|strings|items|data|value)\b"#]
                + names.map { #"\b\#($0)\.(string|strings|items|data|value)\b"# }
            let reads = readers.flatMap { matches($0, in: text) }
            guard !reads.isEmpty else { continue }
            XCTAssertEqual(name, "KeyboardViewController.swift")
            let body = ns.range(of: "private func readClipboard()")
            guard body.location != NSNotFound else { XCTFail("\(name): readClipboard not found"); continue }
            let end = ns.range(of: "\n    }\n", range: NSRange(location: body.location, length: ns.length - body.location))
            guard end.location != NSNotFound else { XCTFail("\(name): end of readClipboard not found"); continue }
            for r in reads {
                XCTAssertTrue(r.location > body.location && r.location < end.location,
                              "\(name): clipboard read outside readClipboard: \(lineText(ns, r))")
            }
        }
    }

    func testUserDefaultsHoldsOnlyTheChangeCountAndTheLanguage() throws {
        for (name, text) in try sources() {
            let ns = text as NSString
            let receivers = [#"UserDefaults\.standard"#, #"UserDefaults\([^)]*\)"#]
                + boundNames(#"UserDefaults\b"#, in: text).map { #"\b\#($0)"# }
            for receiver in receivers {
                for r in matches(receiver + #"\.(set|setValue)\("#, in: text) {
                    let line = lineText(ns, r)
                    XCTAssertTrue(line.contains("changeCount") || line.contains("previousKey"), "\(name): \(line)")
                }
            }
            XCTAssertEqual(matches(#"@AppStorage"#, in: text).count, 0, name)
        }
    }

    private func lineText(_ ns: NSString, _ r: NSRange) -> String {
        let line = ns.lineRange(for: r)
        return "\(ns.substring(to: r.location).components(separatedBy: "\n").count): "
            + ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
