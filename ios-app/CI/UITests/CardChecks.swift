import ProtlyCore
import UIKit
import XCTest

/// keyboard-ui 003, Task 3.5 (docs/plans/2026-10-30-keyboard-ui.md; design Part 3, CI list). Offline: the CI keyboard
/// answers `protly-stub <scenario>` drafts with recorded streams (ios-app/Sources/ProtlyKeyboard/StubActionClient.swift),
/// so the strip and every state of the result card are shown without a key. The host puts each draft in its field
/// with its `fill-N` buttons (`-fills`), the bar's center starts the call, and the strip, the card and their buttons
/// are read from the host's accessibility tree (KeyboardTree.swift), exactly. Every line is PENDING with its readings;
/// checks.py decides (`resolve_card_*`, `resolve_bar_*`, `resolve_app`, `resolve_mem_stream`, test_card_checks.py).
/// Light mode and the large text size come from run-shots.sh's looks helper (`Driver.looks`).
enum Stub {
    /// The same texts as StubScript in StubActionClient.swift (test_card_checks.py compares the two files).
    static let okTranslation = "Thanks so much for today, it really helped me out."
    static let okBack = "오늘 정말 고마워, 큰 도움이 됐어."
    static let cutKept = "Thanks so much for today"
    static let scenarios = ["ok", "error", "cut", "slow"]

    /// Korean after the marker: the bar offers `→ English`, so the strip reads "Translating → English…".
    static func draft(_ scenario: String) -> String { "protly-stub \(scenario) 오늘 정말 고마워" }

    static var fills: String { scenarios.map(draft).joined(separator: "|") }
}

extension PhoneRun {
    static let looks = ["dark", "light"]
    static let cardStates = ["wait", "mid", "done", "err0", "err1"]
    static var cardIDs: [String] {
        looks.flatMap { look in cardStates.map { "card-\($0)-\(look)" } } + ["card-slow", "card-cancel", "mem-stream"]
    }

    static let barIDs = ["hit-1", "bar-dark", "bar-light", "bar-xxl", "app-dark", "app-light"]
    /// The bar drafts of test5e_bar (`fill-1` to `fill-3`): the target pill, then two long or right-to-left names.
    static let barFills = ["ok: 내일 봐 ", "ms: 오늘 고마워 ", "ar: 오늘 고마워 "]

    // MARK: test5d_card

    func checksCard() {
        let ids = Self.cardIDs
        if notReady(ids) || !accessReady(ids) { return }
        defer { d.restoreLooks() }
        for look in Self.looks {
            // Dark is asked for too: a look that did not take must not pass as the other one (checks.py also measures it).
            if !d.looks("appearance", look) {
                for id in ids where id.hasSuffix("-\(look)") { write(id, "FAIL", "unreadable: appearance \(look) not set") }
                continue
            }
            cardOK(look)
            cardError(look)
            cardCut(look)
        }
        if !d.looks("appearance", "dark") { d.log("card: dark not restored before the slow call") }
        cardSlow()
        cardCancel()
        d.clearField()
    }

    /// Puts the scenario's draft in the field (its fill button), checks the bar offers `→ English` and taps it. nil (the
    /// item marked) when the call could not start; else row 1's top.
    private func startStub(_ scenario: String, _ item: Item) -> CGFloat? {
        let draft = Stub.draft(scenario)
        guard let i = Stub.scenarios.firstIndex(of: scenario), fill(i + 1, draft, item) else { return nil }
        return tapCenter(want: "English", item)
    }

    /// Taps the host's `fill-<n>` button and checks the field holds `draft`.
    func fill(_ n: Int, _ draft: String, _ item: Item) -> Bool {
        let button = d.app.buttons["fill-\(n)"]
        guard button.waitForExistence(timeout: 3) else {
            item.markUnreadable("no fill-\(n) button (the host's -fills)")
            return false
        }
        button.tap()
        d.pause(0.8)
        guard let f = field(), f == draft else {
            item.markUnreadable("fill-\(n): field=\(q(field())) want \(q(draft))")
            return false
        }
        return true
    }

    /// The bar's center must offer `want` (the bar follows a field change; once it did not, the keyboard is brought
    /// back, which refreshes it), then it is tapped. Returns row 1's top.
    func tapCenter(want: String, _ item: Item) -> CGFloat? {
        guard let row1 = d.rowOne() else {
            item.markUnreadable("no keyboard")
            return nil
        }
        var center = d.barButtons(row1: row1)?[.center]
        if !(center?.label.contains(want) ?? false) {
            d.log("\(item.id): center \(q(center?.label)) before \(want): bringing the keyboard back")
            d.dismissKeyboard()
            d.pause(1)
            // Not focusField: a tap on the text selects a misspelled word (`protly`, run 67eb25c-78) and the call then
            // polishes the selection. The field's empty bottom-right corner only places the cursor.
            d.field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.9)).tap()
            _ = d.waitForKeyboard()
            d.waitOutStandIn()
            d.pause(0.8)
            center = d.barButtons(row1: row1)?[.center]
        }
        guard let center, center.label.contains(want) else {
            item.markUnreadable("center=\(q(center?.label)) want \(q(want))")
            return nil
        }
        item.note("center=\(q(center.label))")
        d.tapSlot(.center, settle: 0)
        return row1
    }

    /// Polls the tree (up to `timeout`) until `done` holds; the last view and its screenshot.
    func poll(_ timeout: TimeInterval, every: TimeInterval = 0.25,
              until done: (CallView) -> Bool) -> (view: CallView?, screen: XCUIScreenshot, met: Bool) {
        let end = Date().addingTimeInterval(timeout)
        while true {
            let v = d.callView()
            let screen = XCUIScreen.main.screenshot()
            if let v, done(v) { return (v, screen, true) }
            if Date() >= end { return (v, screen, false) }
            d.pause(every)
        }
    }

    /// The look asked for, and a sliver of the keyboard's background left of the bar (inside the side inset, where
    /// neither the strip nor the card draws), so checks.py can confirm the look on c-<id>.png.
    private func noteLook(_ item: Item, _ look: String, _ row1: CGFloat) {
        let left = d.slotRect(.left, row1: row1)
        item.note("look=\(look) side=\(rectText(CGRect(x: 0.5, y: left.minY + 6, width: 2.5, height: left.height - 12)))")
    }

    /// The card or strip closed and the keyboard is still up (a tap that dismissed the keyboard closes nothing).
    private func closed(_ gone: (view: CallView?, screen: XCUIScreenshot, met: Bool)) -> Int {
        gone.met && d.rowOne() != nil ? 1 : 0
    }

    private func noteStrip(_ item: Item, _ v: CallView) {
        let cancel = v.button("Cancel", in: v.strip)
        item.note("strip=\(q(v.stripText)) cancel=\(cancel?.size ?? "none") card=\(v.card.count)")
    }

    private func noteCard(_ item: Item, _ v: CallView) {
        let rows = v.cardRows
        item.note("header=\(q(rows.header.joined(separator: " "))) texts=\(rows.body.count)")
        item.note("buttons=\(q(v.buttons(v.card))) strip=\(v.strip.isEmpty ? 0 : 1)")
    }

    /// card-wait, card-mid and card-done of one look: the strip at once, the first words with the caret, the whole
    /// result. Dark taps Replace (the field takes the translation), light taps Copy, then Cancel.
    private func cardOK(_ look: String) {
        let wait = Item("card-wait-\(look)"), mid = Item("card-mid-\(look)"), done = Item("card-done-\(look)")
        d.clearField()
        guard let row1 = startStub("ok", wait) else {
            finish(wait)
            for it in [mid, done] { it.markUnreadable("the call did not start (card-wait-\(look))"); finish(it) }
            return
        }
        // The stub's first words come about 4.4 s after the tap (a thinking block, then the opening quote).
        d.pause(0.8)
        let w = poll(1.5) { !$0.strip.isEmpty }
        if let v = w.view { noteStrip(wait, v) } else { wait.markUnreadable("tree=unreadable") }
        for it in [wait, mid, done] { noteLook(it, look, row1) }
        wait.markPending()
        finish(wait, screen: w.screen)

        let m = poll(8) { !$0.cardRows.body.isEmpty }
        if let v = m.view, m.met {
            mid.note("text=\(q(v.cardRows.body.first)) final=\(q(Stub.okTranslation))")
            let copy = v.button("Copy", in: v.card)
            mid.note("copy=\(copy.map { $0.enabled ? "enabled" : "disabled" } ?? "none")")
            noteCard(mid, v)
        } else {
            mid.markUnreadable("no card text in 8 s (tree \(m.view == nil ? "unreadable" : "read"))")
        }
        mid.markPending()
        finish(mid, screen: m.screen)

        let f = poll(12) { $0.finished("Replace") }
        guard let v = f.view, f.met else {
            done.markUnreadable("no finished card in 12 s: \(f.view.map { q($0.buttons($0.card)) } ?? "tree unreadable")")
            finish(done, screen: f.screen)
            d.clearField()
            return
        }
        let body = v.cardRows.body
        done.note("text=\(q(body.first)) back=\(q(body.count > 1 ? body[1] : "")) want=\(q(Stub.okTranslation)) "
                  + "want-back=\(q(Stub.okBack))")
        noteCard(done, v)
        done.markPending()
        d.pause(0.6)  // the card's buttons ignore taps for 0.5 s after it appears (AboutMe.saveDelay)
        if look == "dark", let replace = v.button("Replace", in: v.card) {
            d.point(replace.frame.midX, replace.frame.midY).tap()
            d.pause(1.2)
            done.note("after=\(q(field())) want-after=\(q(Stub.okTranslation))")
            // The bar now offers Undo, and keeps offering it after the host empties the field; a key ends it.
            d.type("a")
        } else if let copy = v.button("Copy", in: v.card) {
            d.point(copy.frame.midX, copy.frame.midY).tap()
            let c = poll(3) { $0.button("Copied", in: $0.card) != nil }
            done.note("copied=\(c.met ? 1 : 0)")
            if let cancel = c.view.flatMap({ $0.button("Cancel", in: $0.card) }) {
                d.point(cancel.frame.midX, cancel.frame.midY).tap()
                d.pause(1)
            }
            let gone = poll(2) { $0.card.isEmpty }
            done.note("closed=\(closed(gone)) after=\(q(field())) want-after=\(q(Stub.draft("ok")))")
        }
        finish(done, screen: f.screen)
        d.clearField()
    }

    /// card-err0: an error before any text shows on the strip (with Retry), the keys stay and no card opens.
    private func cardError(_ look: String) {
        let it = Item("card-err0-\(look)")
        let message = ActionError(.overloaded).message
        d.clearField()
        guard let row1 = startStub("error", it) else { return finish(it) }
        noteLook(it, look, row1)
        let e = poll(8) { $0.stripText.contains(message) }
        if let v = e.view, e.met {
            noteStrip(it, v)
            it.note("want-error=\(q(message)) retry=\(v.button("Retry", in: v.strip)?.size ?? "none")")
            if let cancel = v.button("Cancel", in: v.strip) {
                d.point(cancel.frame.midX, cancel.frame.midY).tap()
                let gone = poll(2) { $0.strip.isEmpty }
                it.note("closed=\(closed(gone))")
            }
        } else {
            it.markUnreadable("no error on the strip in 8 s: strip=\(q(e.view?.stripText))")
        }
        it.markPending()
        finish(it, screen: e.screen)
        d.clearField()
    }

    /// card-err1: the connection's error after text arrived: the text stays, dimmed, with the error line under it,
    /// only Copy (and Retry).
    private func cardCut(_ look: String) {
        let it = Item("card-err1-\(look)")
        let message = ActionError(.overloaded).message
        d.clearField()
        guard let row1 = startStub("cut", it) else { return finish(it) }
        noteLook(it, look, row1)
        let e = poll(10) { $0.cardRows.body.contains(message) }
        if let v = e.view, e.met {
            let body = v.cardRows.body
            it.note("kept=\(q(body.first)) want-kept=\(q(Stub.cutKept)) error=\(q(body.last)) want-error=\(q(message))")
            noteCard(it, v)
            d.pause(0.6)
            if let cancel = v.button("Cancel", in: v.card) {
                d.point(cancel.frame.midX, cancel.frame.midY).tap()
                let gone = poll(2) { $0.card.isEmpty }
                it.note("closed=\(closed(gone))")
            }
        } else {
            it.markUnreadable("no error under kept text in 10 s: \(q(e.view?.cardRows.body.joined(separator: " | ")))")
        }
        it.markPending()
        finish(it, screen: e.screen)
        d.clearField()
    }

    /// card-slow: the strip's 8 s line before any text. mem-stream: the keyboard's memory from before the call to the
    /// end of a long streamed reply (memsample.py's samples between the marks; checks.py judges).
    private func cardSlow() {
        let it = Item("card-slow")
        let mem = Item("mem-stream")
        d.clearField()
        guard let i = Stub.scenarios.firstIndex(of: "slow"), fill(i + 1, Stub.draft("slow"), it) else {
            finish(it)
            mem.markUnreadable("the call did not start")
            return finish(mem)
        }
        d.pause(4)  // two samples with the keyboard idle
        d.mark("mem-stream-before")
        guard let row1 = tapCenter(want: "English", it) else {
            finish(it)
            mem.markUnreadable("the call did not start")
            return finish(mem)
        }
        noteLook(it, "dark", row1)
        let t0 = Date()
        d.pause(8.5)
        let s = poll(2) { $0.stripText.contains("Still translating") }
        if let v = s.view { noteStrip(it, v) } else { it.markUnreadable("tree=unreadable") }
        it.note(String(format: "at=%.1fs", Date().timeIntervalSince(t0)))
        it.markPending()
        finish(it, screen: s.screen)
        let first = poll(10, every: 0.5) { !$0.cardRows.body.isEmpty }
        d.mark("mem-stream-start")
        let done = poll(25, every: 1) { $0.finished("Replace") }
        d.mark("mem-stream-end")
        mem.note("first=\(first.met ? "seen" : "none") done=\(done.met ? "seen" : "none")")
        if !first.met || !done.met { mem.markUnreadable("the slow stream did not run to its end") }
        mem.markPending()
        if let cancel = done.view.flatMap({ $0.button("Cancel", in: $0.card) }) {
            d.pause(0.6)
            d.point(cancel.frame.midX, cancel.frame.midY).tap()
        }
        finish(mem, screen: done.screen)
        d.pause(1)
        d.clearField()
    }

    /// card-cancel: `xmark` while the text streams closes the card, a late delta does not bring it back, and the field
    /// keeps the draft.
    private func cardCancel() {
        let it = Item("card-cancel")
        d.clearField()
        guard let row1 = startStub("ok", it) else { return finish(it) }
        noteLook(it, "dark", row1)
        let m = poll(9) { !$0.cardRows.body.isEmpty }
        guard let v = m.view, m.met, let xmark = v.button("Cancel", in: v.strip) else {
            it.markUnreadable("no streaming card with the strip's xmark: \(q(m.view?.stripText))")
            return finish(it, screen: m.screen)
        }
        it.note("card-before=\(v.card.isEmpty ? 0 : 1) xmark=\(xmark.size)")
        d.point(xmark.frame.midX, xmark.frame.midY).tap()
        let gone = poll(2) { $0.card.isEmpty && $0.strip.isEmpty }
        // -1: the tree could not be read, which must not pass as "gone".
        it.note("card-after=\(gone.view.map { $0.card.isEmpty ? 0 : 1 } ?? -1) "
                + "strip-after=\(gone.view.map { $0.strip.isEmpty ? 0 : 1 } ?? -1) keys=\(d.rowOne() != nil ? 1 : 0)")
        d.pause(5)  // past the stub's last delta: nothing may bring the card back
        let late = d.callView()
        it.note("card-late=\(late.map { $0.card.isEmpty ? 0 : 1 } ?? -1)")
        it.note("field=\(q(field())) want-field=\(q(Stub.draft("ok")))")
        it.markPending()
        finish(it, screen: gone.screen)
        d.clearField()
    }

    // MARK: test5e_bar

    func checksBar() {
        let ids = Self.barIDs
        if notReady(ids.filter { !$0.hasPrefix("app-") }) {
            appGuide()
            return
        }
        defer { d.restoreLooks() }
        barLooks(Item("bar-dark"), hit: Item("hit-1"))
        let light = Item("bar-light")
        if d.looks("appearance", "light") {
            barLooks(light, hit: nil)
        } else {
            light.markUnreadable("appearance light not set")
            finish(light)
        }
        d.looks("appearance", "dark")
        barLarge()
        appGuide()
    }

    /// The bar in the current look: `teh` typed (all three slots), then the target pill (`ok: 내일 봐 `). `hit`: also
    /// writes hit-1 from the first state's buttons.
    private func barLooks(_ it: Item, hit: Item?) {
        d.clearField()
        d.type("teh")
        d.pause(0.6)
        guard let row1 = d.rowOne(), let slots = d.barButtons(row1: row1) else {
            it.markUnreadable("no bar to read")
            if let hit { hit.markUnreadable("no bar to read"); finish(hit) }
            return finish(it)
        }
        let first = XCUIScreen.main.screenshot()
        let shot1 = "c-\(it.id)-1.png"
        if !d.savePNG("c-\(it.id)-1", first) { it.markUnreadable("\(shot1) not written") }
        if let hit {
            let list = Slot.allCases.map { (s: Slot) -> String in
                guard let b = slots[s] else { return "\(s.name) none" }
                return "\(s.name) \(b.size) \(q(b.label))"
            }
            hit.note("slots=\(q(list.joined(separator: ", ")))")
            hit.markPending()
            finish(hit, screen: first)
        }
        it.note("shot1=\(q(shot1)) slot1=\(rectText(d.slotRect(.center, row1: row1))) center1=\(q(slots[.center]?.label))")
        d.clearField()
        guard fill(1, Self.barFills[0], it) else { return finish(it) }
        d.pause(0.6)
        let second = XCUIScreen.main.screenshot()
        let shot2 = "c-\(it.id)-2.png"
        if !d.savePNG("c-\(it.id)-2", second) { it.markUnreadable("\(shot2) not written") }
        let center = d.barButtons(row1: row1)?[.center]
        it.note("shot2=\(q(shot2)) slot2=\(rectText(d.slotRect(.center, row1: row1))) center2=\(q(center?.label))")
        it.note("look=\(it.id == "bar-light" ? "light" : "dark") points=\(Int(d.width))")
        it.markPending()
        finish(it, screen: second)
        d.clearField()
    }

    /// The height of one part of the center pill (`→`, `English`), nil when not found.
    private func titleHeight(_ title: String) -> CGFloat? {
        guard let row1 = d.rowOne(), let center = d.barButtons(row1: row1)?[.center], let tree = d.keyboardTree() else {
            return nil
        }
        return d.children(of: center, in: tree).first { $0.label == title }?.frame.height
    }

    /// bar-xxl: the target pill at the extra-extra-large text size with a long name (Bahasa Melayu) and a right-to-left
    /// one (العربية): the arrow before the name, nothing past the slot (checks.py), and the OCR for truncation.
    private func barLarge() {
        let it = Item("bar-xxl")
        // The default size first: the same title row's height, so checks.py sees whether the text size took.
        d.clearField()
        if fill(1, Self.barFills[0], it) {
            d.pause(0.6)
            // The arrow, not the name: the name may shrink to fit (minimumScaleFactor), the arrow keeps the text size.
            it.note("base-h=\(titleHeight("→").map { String(format: "%.1f", $0) } ?? "none")")
        }
        guard d.looks("content_size", "extra-extra-large") else {
            it.markUnreadable("content_size extra-extra-large not set")
            return finish(it)
        }
        defer { d.looks("content_size", Driver.defaultContentSize) }
        var last: XCUIScreenshot?
        for (n, (tag, name)) in [("ms", "Bahasa Melayu"), ("ar", "العربية")].enumerated() {
            d.clearField()
            guard fill(n + 2, Self.barFills[n + 1], it) else { continue }
            d.pause(1)
            guard let row1 = d.rowOne(), let center = d.barButtons(row1: row1)?[.center], let tree = d.keyboardTree() else {
                it.markUnreadable("\(tag): no center pill")
                continue
            }
            let screen = XCUIScreen.main.screenshot()
            last = screen
            if !d.savePNG("c-bar-xxl-\(tag)", screen) { it.markUnreadable("c-bar-xxl-\(tag).png not written") }
            let parts = d.children(of: center, in: tree).sorted { $0.frame.minX < $1.frame.minX }
            it.note("\(tag)-button=\(center.rect) \(tag)-slot=\(rectText(d.slotRect(.center, row1: row1)))")
            it.note("\(tag)-texts=\(q(parts.map { "\($0.label) \($0.rect)" }.joined(separator: "|"))) \(tag)-want=\(q(name))")
            let languages = tag == "ar" ? ["ar-SA", "en-US"] : Reader.languages
            let r = readSlot(.center, it, languages: languages)
            it.note("\(tag)-ocr=\(q(r.text))")
        }
        it.markPending()
        finish(it, screen: last)
        d.clearField()
    }

    /// app-dark and app-light: the container app's guide screen (Sprint 002) at its top and one screen down.
    func appGuide() {
        for look in Self.looks {
            let it = Item("app-\(look)")
            guard d.looks("appearance", look) else {
                it.markUnreadable("appearance \(look) not set")
                finish(it)
                continue
            }
            let app = XCUIApplication(bundleIdentifier: Self.appID)
            app.launch()
            d.pause(2)
            let hero = app.staticTexts["Polish and translate as you type."].waitForExistence(timeout: 5)
            let top = XCUIScreen.main.screenshot()
            if !d.savePNG("c-app-\(look)-1", top) { it.markUnreadable("c-app-\(look)-1.png not written") }
            app.swipeUp()
            d.pause(1.5)
            if !d.savePNG("c-app-\(look)-2") { it.markUnreadable("c-app-\(look)-2.png not written") }
            it.note("hero=\(hero ? 1 : 0) shot1=\(q("c-app-\(look)-1.png")) shot2=\(q("c-app-\(look)-2.png")) look=\(look)")
            app.terminate()
            it.markPending()
            finish(it, screen: top)
        }
        d.looks("appearance", "dark")
        d.launch()
        d.ensureProtly()
    }

    private func rectText(_ r: CGRect) -> String {
        String(format: "{%.1f,%.1f,%.1f,%.1f}", r.minX, r.minY, r.width, r.height)
    }
}
