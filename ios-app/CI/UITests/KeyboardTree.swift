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

    /// Texts that are not a button or inside one (a button's title is a static text child of it), top to bottom.
    func texts(_ elements: [KeyElement]) -> [KeyElement] {
        let buttons = elements.filter { $0.type == .button }.map(\.frame)
        return elements
            .filter { $0.type != .button && !$0.label.isEmpty }
            .filter { e in !buttons.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(e.frame) } }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
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
    /// The keyboard's elements (frames from `top` down, points) in one snapshot of the app's tree; nil when the
    /// snapshot failed. `top` defaults to the band above row 1 as last measured.
    func keyboardTree(top: CGFloat? = nil) -> [KeyElement]? {
        let limit = top ?? ((fixedRow1 ?? Self.lastRow1 ?? 564) - Geo.band - 6)
        let root: XCUIElementSnapshot
        do {
            root = try app.snapshot()
        } catch {
            log("tree snapshot failed: \(error)")
            return nil
        }
        var out: [KeyElement] = []
        func walk(_ s: XCUIElementSnapshot, _ part: String?) {
            let p = s.identifier.hasPrefix("protly-") ? s.identifier : part
            let f = s.frame
            if f.minY >= limit, f.width > 0, f.height > 0, s.elementType != .window, s.elementType != .application {
                out.append(KeyElement(type: s.elementType, label: s.label, frame: f, enabled: s.isEnabled, part: p))
            }
            for c in s.children { walk(c, p) }
        }
        walk(root, nil)
        return out
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
    /// later method (a restarted runner included) can put them back. false when no answer came.
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
                let ok = line.split(separator: " ").dropFirst().first == "ok"
                let changed = out.appendingPathComponent("looks-changed.txt")
                if ok && (value == "dark" || value == Self.defaultContentSize) {
                    var rest = ((try? String(contentsOf: changed, encoding: .utf8)) ?? "").split(separator: "\n")
                    rest.removeAll { $0.hasPrefix(setting + " ") }
                    if rest.isEmpty {
                        try? FileManager.default.removeItem(at: changed)
                    } else {
                        try? rest.joined(separator: "\n").write(to: changed, atomically: true, encoding: .utf8)
                    }
                } else if ok {
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

    /// Dark and the default text size again, when an earlier method left them changed (looks-changed.txt).
    func restoreLooks() {
        let changed = out.appendingPathComponent("looks-changed.txt")
        guard let text = try? String(contentsOf: changed, encoding: .utf8), !text.isEmpty else { return }
        log("restoring the looks an earlier method left: \(text.replacingOccurrences(of: "\n", with: "; "))")
        if text.contains("appearance ") { looks("appearance", "dark") }
        if text.contains("content_size ") { looks("content_size", Self.defaultContentSize) }
    }
}
