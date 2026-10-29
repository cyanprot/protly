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
                throw XCTSkip("\(dir) not found next to ProtlyCore")
            }
            for name in names.sorted() where name.hasSuffix(".swift") && name != "Secrets.swift" {
                out.append((name, try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)))
            }
        }
        XCTAssertTrue(out.contains { $0.0 == "KeyboardViewController.swift" })
        return out
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
            // Names bound to the pasteboard: `let pb = UIPasteboard.general`.
            let names = matches(#"let (\w+) = UIPasteboard\.general\b"#, in: text).compactMap { r -> String? in
                let re = try! NSRegularExpression(pattern: #"let (\w+) ="#)
                guard let m = re.firstMatch(in: text, range: r) else { return nil }
                return ns.substring(with: m.range(at: 1))
            }
            let readers = [#"UIPasteboard\.general\.(string|strings|items|data|value)\b"#]
                + names.map { #"\b\#($0)\.(string|strings|items|data|value)\b"# }
            let reads = readers.flatMap { matches($0, in: text) }
            guard !reads.isEmpty else { continue }
            XCTAssertEqual(name, "KeyboardViewController.swift")
            let body = ns.range(of: "private func readClipboard()")
            XCTAssertNotEqual(body.location, NSNotFound)
            let end = ns.range(of: "\n    }\n", range: NSRange(location: body.location, length: ns.length - body.location))
            for r in reads {
                XCTAssertTrue(r.location > body.location && r.location < end.location,
                              "\(name): clipboard read outside readClipboard: \(lineText(ns, r))")
            }
        }
    }

    func testUserDefaultsKeepsNoText() throws {
        for (name, text) in try sources() {
            let ns = text as NSString
            for r in matches(#"\.set\("#, in: text) {
                let line = lineText(ns, r)
                guard line.contains("UserDefaults") || line.contains("d.set(") else { continue }
                XCTAssertTrue(line.contains("changeCount") || line.contains("previousKey"), "\(name): \(line)")
            }
        }
    }

    private func lineText(_ ns: NSString, _ r: NSRange) -> String {
        let line = ns.lineRange(for: r)
        return "\(ns.substring(to: r.location).components(separatedBy: "\n").count): "
            + ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
