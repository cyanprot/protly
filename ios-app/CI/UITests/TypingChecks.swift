import UIKit
import XCTest

/// typing-fixes 004 (docs/plans/2026-10-30-typing-fixes.md, Sprint 004): the simulator proof of the plain-text
/// composition (sprint 001) and the space trackpad (sprint 003), on the CI host's extra screens (HostApp.swift,
/// `-screen web` and `-screen uikit`).
///
/// - test5a_web: dark-1 (the word being typed has the same ink as after a space, no underline, on the dark web page)
///   and ret-<step>-<field> (Return in a textarea, a form input and an Enter-to-send composer keeps the text;
///   enter-clears-web.md, "Simulator scenario").
/// - test5b_menu: menu-0 (Apple's keyboard, the control), menu-1 (Protly, a double-tap on the last word typed with
///   no space shows Copy) and menu-4 (ㅎ then replaces the selection); edit-menu-missing.md 4.3, S0, S1 and S4.
/// - test5c_pad: pad-1 to pad-3, the space trackpad (space-trackpad.md P3 and P5).
///
/// Every line is PENDING with its readings; checks.py decides (resolve_dark, resolve_ret, resolve_menu,
/// resolve_menu4, resolve_pad). A step that did not happen makes the line FAIL unreadable.
extension PhoneRun {
    /// Return steps (enter-clears-web.md): the text, then Return after `gap` seconds (0.05: at once; XCUITest's own
    /// time to make a tap comes on top, `gap=` in the line is what it was).
    static let returnSteps: [(n: Int, text: String, gap: TimeInterval)] = [
        (1, "안녕", 0.05), (2, "hello 안녕", 0.05), (3, "hello 안녕 ", 0.05), (4, "hello 안녕", 0.3), (5, "ㅇㅋ", 0.05),
    ]
    static let padText = "hello world hello world "

    /// A PENDING line for checks.py, or FAIL unreadable when a step did not happen (the driver's problems).
    func pending(_ id: String, _ evidence: String) {
        let problems = d.takeProblems()
        if problems.isEmpty {
            write(id, "PENDING", evidence)
        } else {
            write(id, "FAIL", "unreadable: problems=\(q(problems.joined(separator: "; "))) \(evidence)")
        }
    }

    /// FAIL unreadable with the driver's problems.
    func unreadableLine(_ id: String, _ why: String) {
        let problems = d.takeProblems()
        write(id, "FAIL", "unreadable: \(why)" + (problems.isEmpty ? "" : " problems=\(q(problems.joined(separator: "; ")))"))
    }

    /// Protly up on the field just tapped: waits out a stand-in, else the globe's list or globe taps.
    func protlyUp() -> Bool {
        guard d.waitForKeyboard() else {
            d.fail("no keyboard after tapping the field")
            return false
        }
        d.waitOutStandIn()
        if d.current() == .protly || d.pick(.protly) || d.cycle(to: .protly, taps: 3) { return true }
        d.fail("protly keyboard not reached")
        return false
    }

    // MARK: test5a_web

    func checksWeb() {
        let retIDs = Self.returnSteps.flatMap { s in WebPage.fields.map { "ret-\(s.n)-\($0)" } }
        let ids = ["dark-1"] + retIDs
        if notReady(ids) { return }
        // Row 1 on the solid host. On the web screen the form accessory bar sits above the keyboard and would read
        // as its top; the keyboard pins its own height, so row 1 is the same on both screens.
        guard let row1 = d.rowOne() else {
            for id in ids { unreadableLine(id, "no row 1 on the host before the web screen") }
            return
        }
        d.app.terminate()
        d.launch(arguments: ["-screen", "web"])
        d.fixedRow1 = row1
        defer { d.fixedRow1 = nil }
        let web = WebPage(d: d)
        guard web.waitLoaded() else {
            for id in ids { unreadableLine(id, "the web page did not load (state \(q(web.raw())), rects \(q(d.probeValue("web-rects"))))") }
            return
        }
        d.log("web page: rects \(d.probeValue("web-rects") ?? "none")")

        // dark-1 (marked-text-dark.md, Simulator scenario 2): dkssud with no space, then a space, in the composer.
        web.clear()
        if web.focus("composer"), protlyUp() {
            d.type("안녕")
            d.pause(0.8)
            let typing = XCUIScreen.main.screenshot()
            let before = web.text("composer")
            d.type(" ")
            d.pause(0.8)
            let space = XCUIScreen.main.screenshot()
            let after = web.text("composer")
            let saved = d.savePNG("c-dark-1-1-typing", typing) && d.savePNG("c-dark-1-2-space", space)
            if saved, let r = web.rect("composer") {
                // Inside the border and the rounded corners: only the text's line.
                let inner = r.insetBy(dx: 4, dy: 4)
                pending("dark-1", "typing=\"c-dark-1-1-typing.png\" space=\"c-dark-1-2-space.png\" rect="
                        + String(format: "%.1f,%.1f,%.1f,%.1f", inner.minX, inner.minY, inner.width, inner.height)
                        + " points=\(Int(d.width)) before=\(q(before)) after=\(q(after))")
            } else {
                unreadableLine("dark-1", saved ? "no composer frame" : "c-dark-1-*.png not written")
            }
        } else {
            unreadableLine("dark-1", "composer not focused with Protly")
        }

        // ret-<step>-<field>: in each field the five steps; the page's state right after Return.
        for field in WebPage.fields {
            for step in Self.returnSteps {
                let id = "ret-\(step.n)-\(field)"
                web.clear()
                guard web.focus(field), protlyUp() else {
                    unreadableLine(id, "\(field) not focused with Protly")
                    continue
                }
                d.mark(id)  // web-events.txt lines carry the same clock (t= in ms)
                d.type(step.text + "\n", lastGap: step.gap)
                d.pause(1.0)
                guard let s = web.state() else {
                    unreadableLine(id, "no page state after Return (\(q(web.raw())))")
                    continue
                }
                var ev = "want=\(q(step.text))"
                if let b = (s["atReturn"] as? [String: Any])?[field] as? String { ev += " before=\(q(b))" }
                ev += " value=\(q(s[field] as? String))"
                let sent = s["sent"] as? [String] ?? []
                ev += " sent-count=\(sent.count)" + (sent.last.map { " sent=\(q($0))" } ?? "")
                let submitted = s["submitted"] as? [String] ?? []
                ev += " submit-count=\(submitted.count)" + (submitted.last.map { " submitted=\(q($0))" } ?? "")
                ev += String(format: " gap=%.2fs", d.lastGap)
                ev += " ev=\(q((s["trace"] as? [String] ?? []).joined(separator: " ")))"
                pending(id, ev)
            }
        }
        web.clear()
    }

    // MARK: test5b_menu (the UITextView screen)

    func checksMenu() {
        if notReady(["menu-0", "menu-1", "menu-4"]) { return }

        // S0, the control: Apple's keyboard, "hello there", a double-tap on "hello". If it fails, the harness is wrong.
        d.clearField()
        d.switchToEnglish()
        if d.current() == .english, typeOnApple("hello there") {
            d.pause(0.8)
            let typed = field()
            let menu = doubleTapWord("first-word")
            pending("menu-0", "menu=\(q(menu.joined(separator: ","))) sel=\(q(d.probeValue("sel"))) field=\(q(typed)) "
                    + "keyboard=english")
        } else {
            unreadableLine("menu-0", "Apple's English keyboard not reached or not typed on (\(d.current().rawValue))")
        }
        d.clearField()  // the tap also closes the menu
        if !d.pick(.protly) && !d.cycle(to: .protly, taps: 3) { d.fail("protly keyboard not reached after menu-0") }

        // S1: Protly, "안녕 오늘" with no space, a double-tap on the last word (the word just typed).
        d.clearField()
        d.type("안녕 오늘")
        d.pause(0.5)
        let typed = field()
        let menu = doubleTapWord("last-word")
        let sel = d.probeValue("sel")
        pending("menu-1", "menu=\(q(menu.joined(separator: ","))) sel=\(q(sel)) marked=\(q(d.probeValue("marked"))) "
                + "field=\(q(typed)) after=\(q(field()))")

        // S4 (H3): ㅎ now replaces the selected word.
        d.type("ㅎ")
        d.pause(0.5)
        pending("menu-4", "field=\(q(field())) sel-before=\(q(sel)) sel=\(q(d.probeValue("sel")))")
        d.clearField()
    }

    /// Apple's keyboard: its keys are in the accessibility tree, so they are tapped by label (a letter, either case)
    /// or, for space, by identifier (its label is " ", run 8632699-72's tree-english.txt).
    private func typeOnApple(_ text: String) -> Bool {
        for ch in text {
            let predicate = ch == " " ? NSPredicate(format: "identifier == 'space' OR label == ' '")
                : NSPredicate(format: "label ==[c] %@", String(ch))
            let key = d.app.keyboards.keys.matching(predicate).firstMatch
            guard key.waitForExistence(timeout: 2) else {
                d.fail("Apple's keyboard has no \(String(reflecting: ch)) key")
                return false
            }
            key.tap()
            d.pause(0.15)
        }
        return true
    }

    /// Double-taps the word whose frame the host publishes (`first-word`, `last-word`); the edit menu's items.
    private func doubleTapWord(_ probe: String) -> [String] {
        guard let r = Self.rect(d.probeValue(probe)) else {
            d.fail("no \(probe) frame from the host")
            return []
        }
        d.point(r.midX, r.midY).doubleTap()
        d.pause(1.0)  // the menu shows after the gesture ends
        let items = editMenu()
        d.log("double-tap on \(probe) \(NSCoder.string(for: r)): menu \(items)")
        return items
    }

    /// The host's edit menu items within `timeout` (it belongs to the host, so XCUITest sees it).
    private func editMenu(timeout: TimeInterval = 3) -> [String] {
        func has(_ label: String) -> Bool {
            d.app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch.exists
        }
        let end = Date().addingTimeInterval(timeout)
        while !has("Copy") && Date() < end { d.pause(0.4) }
        d.dumpOnce("edit-menu")
        return ["Copy", "Cut", "Paste", "Select All", "Look Up", "Translate", "Share\u{2026}"].filter { has($0) }
    }

    // MARK: test5c_pad (the UITextView screen)

    func checksPad() {
        if notReady(["pad-1", "pad-2", "pad-3"]) { return }
        // pad-1: a 1 s press on space, then a slow drag 90 pt left: about 15 narrow characters (6 pt each).
        let ref = padDrag("pad-1", text: Self.padText, dx: -90, dy: 0, speed: 120) ?? 0
        // pad-2: the same drag with the finger rising 80 pt: it must keep moving (space-trackpad.md R1, P3).
        _ = padDrag("pad-2", text: Self.padText, dx: -90, dy: -80, speed: 120, extra: " ref=\(ref)")
        // pad-3: 안녕 with no space, one step left (12 pt a syllable): 안|녕, nothing lost (P5).
        _ = padDrag("pad-3", text: "안녕", dx: -20, dy: 0, speed: 60, extra: " want-sel=1")
        d.clearField()
    }

    /// Types `text` (once more if a tap was lost: run 8632699-72 typed `wrld` once), reads the field and the caret,
    /// holds and drags on space, writes the PENDING line: the drag must leave the field as it was before it. Returns
    /// the caret's move left.
    private func padDrag(_ id: String, text: String, dx: CGFloat, dy: CGFloat, speed: CGFloat,
                         extra: String = "") -> Int? {
        var typed: String?
        var tries = 0
        repeat {
            tries += 1
            d.clearField()
            d.type(text)
            d.pause(0.5)
            typed = field()
        } while typed != text && tries < 2
        let sel0 = Self.selection(d.probeValue("sel"))
        d.dragSpace(hold: 1.0, dx: dx, dy: dy, speed: speed)
        d.pause(0.6)
        let sel1 = d.probeValue("sel")
        var ev = "want=\(q(typed)) field=\(q(field())) sel0=\(sel0.map { String($0.location) } ?? "unreadable") "
        ev += "sel1=\(q(sel1)) marked=\(q(d.probeValue("marked")))"
        if tries > 1 || typed != text { ev += " asked=\(q(text)) typing-tries=\(tries)" }
        ev += String(format: " drag=%.0f,%.0f speed=%.0f", dx, dy, speed) + extra
        pending(id, ev)
        guard let s0 = sel0, let s1 = Self.selection(sel1) else { return nil }
        return s0.location - s1.location
    }

    /// "location,length" (the host's `sel`).
    static func selection(_ s: String?) -> (location: Int, length: Int)? {
        let parts = (s ?? "").split(separator: ",").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// "x,y,w,h" (the host's word frames).
    static func rect(_ s: String?) -> CGRect? {
        let v = (s ?? "").split(separator: ",").compactMap { Double($0) }
        guard v.count == 4, v[2] > 0, v[3] > 0 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
}

/// The host's web composer screen (`-screen web`, web-composer.html), read through the `web-state` and `web-rects`
/// probes: exact text, unlike the web view's accessibility tree.
@MainActor
struct WebPage {
    static let fields = ["textarea", "input", "composer"]
    let d: Driver

    func raw() -> String? {
        d.probeValue("web-state")
    }

    func state() -> [String: Any]? {
        guard let s = raw(), let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func text(_ field: String) -> String? {
        state()?[field] as? String
    }

    /// A field's frame in screen points.
    func rect(_ field: String) -> CGRect? {
        guard let s = d.probeValue("web-rects"), let data = s.data(using: .utf8),
              let all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let v = (all[field] as? [NSNumber])?.map({ CGFloat($0.doubleValue) }), v.count == 4,
              v[2] > 0, v[3] > 0 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    /// The page posted its state and the fields' frames.
    func waitLoaded(timeout: TimeInterval = 20) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if text("composer") != nil, rect("composer") != nil { return true }
            d.pause(0.5)
        } while Date() < end
        return false
    }

    /// Taps a field's center (an empty field puts the caret at its start).
    func focus(_ field: String) -> Bool {
        guard let r = rect(field) else {
            d.fail("no \(field) frame on the web page")
            return false
        }
        d.point(r.midX, r.midY).tap()
        d.pause(0.6)
        return true
    }

    /// The host's Clear: every field, the sent and submitted lists, the step's trace.
    func clear() {
        let button = d.app.buttons["clear"]
        guard button.waitForExistence(timeout: 2) else {
            d.fail("clear button not found")
            return
        }
        button.tap()
        d.pause(0.5)
        guard let s = state() else {
            d.fail("no page state after Clear")
            return
        }
        if Self.fields.contains(where: { !((s[$0] as? String) ?? "?").isEmpty }) {
            d.fail("Clear left text on the web page: \(q(raw()))")
        }
    }
}
