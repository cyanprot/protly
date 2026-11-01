import UIKit
import XCTest

/// One of Protly's views as the host's accessibility tree carries it. The keyboard's SwiftUI views are in the host
/// app's tree with their labels and frames (tree-06: the bar's slot buttons and the keys), so the result card, the
/// strip and the panel are read here exactly, where OCR used to guess (keyboard-ui 003). `part` is the nearest
/// `protly-...` identifier on the element or above it: `protly-card`, `protly-strip` or `protly-panel`
/// (ResultCard.swift, ProgressStrip.swift, Panel.swift; identifiers only, nothing VoiceOver reads).
struct KeyElement {
    let type: XCUIElement.ElementType
    let label: String
    let frame: CGRect
    let enabled: Bool
    let part: String?

    var size: String { String(format: "%.1fx%.1f", frame.width, frame.height) }

    var rect: String { String(format: "{%.1f,%.1f,%.1f,%.1f}", frame.minX, frame.minY, frame.width, frame.height) }
}

/// The strip, the result card and the panel at one moment.
struct CallView {
    let elements: [KeyElement]

    func part(_ name: String) -> [KeyElement] { elements.filter { $0.part == name } }

    var strip: [KeyElement] { part("protly-strip") }
    var card: [KeyElement] { part("protly-card") }
    var panel: [KeyElement] { part("protly-panel") }

    func button(_ label: String, in elements: [KeyElement]) -> KeyElement? {
        elements.first { $0.type == .button && $0.label == label }
    }

    /// Static texts that are not inside a button (a button's title is a static text child of it), top to bottom.
    /// Only static texts: the card's ScrollView adds an element labeled "Vertical scroll bar, 1 page" (run 67eb25c-78).
    func texts(_ elements: [KeyElement]) -> [KeyElement] {
        let buttons = elements.filter { $0.type == .button }.map(\.frame)
        return elements
            .filter { $0.type == .staticText && !$0.label.isEmpty }
            .filter { e in !buttons.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(e.frame) } }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// The card is finished: its `primary` button (Replace, Insert) is there and enabled, and the strip is gone.
    /// While the text streams the card draws the same button disabled, so its presence alone proves nothing.
    func finished(_ primary: String) -> Bool {
        strip.isEmpty && button(primary, in: card)?.enabled == true
    }

    /// The strip's label line(s), joined with spaces ("Translating → English…", the 8 s line, an error line).
    var stripText: String { texts(strip).map(\.label).joined(separator: " ") }

    /// The card's header row (`→`, the target) and the texts under it (the translation, the back translation, the
    /// error or field-changed line), each top to bottom.
    var cardRows: (header: [String], body: [String]) {
        let all = texts(card)
        guard let top = all.first?.frame.midY else { return ([], []) }
        let header = all.filter { abs($0.frame.midY - top) < 4 }
        let body = all.filter { abs($0.frame.midY - top) >= 4 }
        return (header.sorted { $0.frame.minX < $1.frame.minX }.map(\.label), body.map(\.label))
    }

    /// The panel's or the card's buttons with their sizes, `Cancel 108.0x44.0,Copy 60.0x44.0`.
    func buttons(_ elements: [KeyElement]) -> String {
        elements.filter { $0.type == .button }.sorted { $0.frame.minX < $1.frame.minX }
            .map { "\($0.label) \($0.size)\($0.enabled ? "" : " disabled")" }.joined(separator: ",")
    }
}

@MainActor
extension Driver {
    /// The keyboard's elements (frames that reach below `top`, points), read from the app's debug description: the
    /// text the tree-*.txt files hold, which carries the keyboard's remote views. `app.snapshot()` did not (run
    /// d103b93-77: the bar's buttons, plain in tree-protly.txt, were not among its children). `top` defaults to the
    /// band above row 1 as last measured. nil when the description has no element at all.
    func keyboardTree(top: CGFloat? = nil) -> [KeyElement]? {
        let limit = top ?? ((fixedRow1 ?? Self.lastRow1 ?? 564) - Geo.band - 6)
        let elements = KeyTreeText.parse(app.debugDescription)
        guard !elements.isEmpty else {
            log("tree: no element in the app's description")
            return nil
        }
        // maxY: a long card text scrolled up inside the card starts above the band and still counts.
        return elements.filter { $0.frame.maxY > limit && $0.frame.width > 0 && $0.frame.height > 0 }
    }

    func callView() -> CallView? { keyboardTree().map(CallView.init) }

    /// The bar's buttons (the band above row 1) by slot: the button whose center is in the slot's rect.
    func barButtons(row1: CGFloat) -> [Slot: KeyElement]? {
        guard let tree = keyboardTree(top: row1 - Geo.band - 6) else { return nil }
        var out: [Slot: KeyElement] = [:]
        for slot in Slot.allCases {
            let r = slotRect(slot, row1: row1).insetBy(dx: 0, dy: -8)
            out[slot] = tree.first {
                $0.type == .button && $0.frame.maxY <= row1 + 1 && r.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }
        }
        return out
    }

    /// The elements drawn in a bar slot's button (its title, the arrow, a symbol): their centers are inside it, so a
    /// title that overflows the slot still counts, with its frame past the button's.
    func children(of button: KeyElement, in tree: [KeyElement]) -> [KeyElement] {
        tree.filter { $0.type != .button && button.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    // MARK: Appearance and text size (run-shots.sh's looks helper)

    /// Asks run-shots.sh to run `xcrun simctl ui <device> <setting> <value>` (the test runs inside the simulator and
    /// cannot): a line in looks-requests.txt, answered in looks-acks.txt. Only `appearance light|dark` and
    /// `content_size <size>` are honored. Leaves looks-changed.txt while not back at dark and the default size, so a
    /// later method (a restarted runner included) can put them back. false unless simctl read the new value back.
    @discardableResult
    func looks(_ setting: String, _ value: String, timeout: TimeInterval = 30) -> Bool {
        let n = Int(Date().timeIntervalSince1970 * 1000)
        append("\(n) \(setting) \(value)", to: "looks-requests.txt")
        let acks = out.appendingPathComponent("looks-acks.txt")
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let text = (try? String(contentsOf: acks, encoding: .utf8)) ?? ""
            if let line = text.split(separator: "\n").first(where: { $0.hasPrefix("\(n) ") }) {
                log("looks \(setting) \(value): \(line)")
                pause(1.5)  // the views take the new traits
                // `<n> ok <setting> now <value>`: simctl read the setting back, and it must be the one asked for.
                let words = line.split(separator: " ").map(String.init)
                let ok = words.count >= 5 && words[1] == "ok" && words[3] == "now" && words[4] == value
                if words.count >= 2 && words[1] == "ok" && !ok { log("looks \(setting) \(value): simctl reads back another value") }
                // Any change counts, even one simctl did not confirm: the next method puts dark and the default back.
                if !(value == "dark" || value == Self.defaultContentSize) {
                    append("\(setting) \(value)", to: "looks-changed.txt")
                }
                return ok
            }
            pause(0.5)
        }
        log("looks \(setting) \(value): no answer in \(Int(timeout)) s")
        return false
    }

    /// The simulator's default text size (simctl's name for UIContentSizeCategoryLarge).
    static let defaultContentSize = "large"

    /// Dark and the default text size again, once any method asked for another look (looks-changed.txt, appended to
    /// and never cleared): both are asked for every time, so a lost write cannot leave a later method in light mode.
    func restoreLooks() {
        let changed = out.appendingPathComponent("looks-changed.txt")
        guard let text = try? String(contentsOf: changed, encoding: .utf8), !text.isEmpty else { return }
        log("putting dark and the default text size back (asked for before: \(text.replacingOccurrences(of: "\n", with: "; ")))")
        if !looks("appearance", "dark") { log("looks: dark not confirmed") }
        if !looks("content_size", Self.defaultContentSize) { log("looks: the default text size not confirmed") }
    }
}

/// XCUITest's element description, one element per line: `<indent>Button, 0x.., {{x, y}, {w, h}}, identifier: 'id',
/// label: 'text', value: v, Disabled`. A label with line breaks runs on over the next lines (the About me confirm
/// text, run 236dc9a-80), so a line that starts no element continues the one before. The indent gives the nesting, so
/// each element gets the nearest `protly-` identifier on itself or above it.
enum KeyTreeText {
    private static let start = try! NSRegularExpression(pattern: #"^ *(?:\u2192)?[A-Za-z]+(?: \([^)]*\))?, 0x[0-9a-fA-F]+, \{\{"#)
    private static let line = try! NSRegularExpression(
        pattern: #"^( *)(?:\u2192)?([A-Za-z]+)(?: \([^)]*\))?, 0x[0-9a-fA-F]+, \{\{(-?[0-9.]+), (-?[0-9.]+)\}, \{([0-9.]+), ([0-9.]+)\}\}(.*)$"#,
        options: [.dotMatchesLineSeparators])

    /// The description's elements, each with the lines its label runs on over.
    static func entries(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let ns = raw as NSString
            if start.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) != nil || out.isEmpty {
                out.append(raw)
            } else {
                out[out.count - 1] += "\n" + raw
            }
        }
        return out
    }
    /// What may follow a quoted value: the next attribute, a flag, or the end of the line.
    private static let end = #"'(?=$|, (?:identifier|label|value|placeholderValue|title): |, (?:Disabled|Selected|Keyboard Focused|Focused)\b)"#

    static func parse(_ text: String) -> [KeyElement] {
        var out: [KeyElement] = []
        var stack: [(indent: Int, part: String?)] = []
        for raw in entries(text) {
            let ns = raw as NSString
            guard let m = line.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { continue }
            func group(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
            let indent = group(1).count
            let rest = group(7)
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
            let identifier = quoted("identifier", in: rest) ?? ""
            let part = identifier.hasPrefix("protly-") ? identifier : stack.last?.part
            stack.append((indent, part))
            let type: XCUIElement.ElementType
            switch group(2) {
            case "Button": type = .button
            case "StaticText": type = .staticText
            case "Image": type = .image
            case "Window": type = .window
            case "Application": type = .application
            default: type = .other
            }
            guard type != .window && type != .application,
                  let x = Double(group(3)), let y = Double(group(4)), let w = Double(group(5)), let h = Double(group(6))
            else { continue }
            out.append(KeyElement(type: type, label: quoted("label", in: rest) ?? "",
                                  frame: CGRect(x: x, y: y, width: w, height: h),
                                  enabled: !rest.contains(", Disabled"), part: part))
        }
        return out
    }

    /// The value of `name: '...'` in the rest of a line; a value may hold quotes and commas.
    static func quoted(_ name: String, in rest: String) -> String? {
        guard let start = rest.range(of: ", \(name): '") else { return nil }
        let tail = String(rest[start.upperBound...])
        guard let close = tail.range(of: end, options: .regularExpression) else { return nil }
        return String(tail[..<close.lowerBound])
    }
}
