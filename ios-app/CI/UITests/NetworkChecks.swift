import UIKit
import XCTest

/// Sprint 002 of docs/plans/2026-10-30-sim-phone-checks.md: Full Access (Task 2.2), the network checks with the CI
/// key and the container app's about-me note (Task 2.3), the request cap (Task 2.4).
///
/// Panel buttons are inside the keyboard, so XCUITest cannot see them: the test polls Vision OCR of the panel every
/// 0.5 s for the button's label and taps the label's word box from that same screenshot. Text that reaches the field
/// is read through XCUITest (exact). Model output goes into the CHECK line as `<group>#<try>="..."` and checks.py's
/// script rules decide (RULES); the test repeats those rules only to decide on its one retry. Nothing here prints a
/// request, a header or the key: the panel shows protly's own fixed error messages, never a response body.
extension PhoneRun {
    static let appID = "com.northprot.protly.ciapp"
    /// Fictional and fixed (plan Task 2.3); never the user's note.
    static let testNote = "I run Moonbeam Kiln (문빔 킬른), a pottery studio in Victoria."
    /// A Korean draft with the note's name in Hangul (7.7-2, 7.7-3).
    static let kiln = Draft(code: nil, text: "우리 문빔 킬른 다음 주에 오픈해 ")
    /// Plan Task 2.4: at most 60 API requests per run.
    static let requestCap = 60
    static var requests = 0
    /// Set by test0_access; nil when it did not run.
    static var fullAccess: Bool?
    static var fullAccessHow = "not checked (test0_access did not run)"
    /// run-shots.sh passes NETWORK=1 when the workflow wrote Secrets.swift with the CI key (HAS_KEY=true).
    static var network: Bool { ProcessInfo.processInfo.environment["NETWORK"] == "1" }

    // MARK: Full Access and requests

    /// test0_access: Full Access read in Settings and turned on there when off (plan Task 2.2).
    func fullAccess() {
        let r = d.fullAccessInSettings()
        Self.fullAccess = r.on
        Self.fullAccessHow = r.how
        let line = "full access: \(r.on ? "on" : "off"), \(r.how)"
        d.log(line)
        d.append(line, to: "network.txt")
    }

    /// Counts a tap that sends a request; false (and nothing is tapped) once the cap is reached.
    func send(_ item: Item) -> Bool {
        guard Self.requests < Self.requestCap else {
            d.log("\(item.id): request cap \(Self.requestCap) reached")
            return false
        }
        Self.requests += 1
        d.log("request \(Self.requests) of at most \(Self.requestCap) (\(item.id))")
        return true
    }

    /// A network group can run: SKIP every ID without the key, FAIL unreadable without Full Access (the CI's fault).
    func networkReady(_ ids: [String]) -> Bool {
        guard Self.network else {
            for id in ids { write(id, "SKIP", "no network key") }
            return false
        }
        return accessReady(ids)
    }

    func accessReady(_ ids: [String]) -> Bool {
        guard Self.fullAccess == true else {
            for id in ids { write(id, "FAIL", "unreadable: full access not on (\(Self.fullAccessHow))") }
            return false
        }
        return true
    }

    /// Hides the keyboard and brings Protly back on the host's field: any panel closes (viewWillDisappear).
    func resetKeyboard() {
        d.dismissKeyboard()
        d.pause(1)
        d.focusField()
        d.waitOutStandIn()
        if d.current() != .protly { d.ensureProtly() }
    }

    // MARK: The panel

    struct PanelRead {
        let screen: XCUIScreenshot
        let seen: Seen?
        let file: String?
    }

    /// Screenshot and OCR of the panel region; saved as c-<id>-<n>-<name>.png when `save` names it.
    /// `only`: OCR just that region (the button band, a few times faster than the whole panel: run 30 needed
    /// seconds per whole-panel reading). `screen`: read an earlier screenshot instead of taking one.
    func readPanel(_ row1: CGFloat, _ item: Item, save name: String?, only region: CGRect? = nil,
                   screen given: XCUIScreenshot? = nil) -> PanelRead {
        let screen = given ?? XCUIScreen.main.screenshot()
        var file: String?
        if let name {
            let f = item.nextShot(name)
            if d.savePNG(f, screen) { file = f + ".png" }
        }
        let seen = reader.read(in: region ?? d.panelRect(row1: row1), of: screen, points: d.width,
                               label: "\(item.id) \(name ?? "poll")", quiet: name == nil)
        return PanelRead(screen: screen, seen: seen, file: file)
    }

    /// Polls the panel's button band every 0.5 s, up to `timeout`, until it shows one of `labels`. Returns the whole
    /// panel's reading of that screenshot (saved), the label, its word box and when the screenshot was taken.
    func waitPanel(_ row1: CGFloat, _ item: Item, for labels: [String], timeout: TimeInterval = 30,
                   name: String = "panel") -> (read: PanelRead, label: String?, rect: CGRect?, at: Date) {
        let band = d.panelButtonBand(row1: row1)
        let end = Date().addingTimeInterval(timeout)
        while true {
            let at = Date()
            let r = readPanel(row1, item, save: nil, only: band)
            if let seen = r.seen {
                for label in labels {
                    if let rect = seen.word(label, in: band) {
                        let whole = readPanel(row1, item, save: nil, screen: r.screen)
                        return (savePanel(whole, item, name), label, rect, at)
                    }
                }
            }
            if Date() >= end {
                let whole = readPanel(row1, item, save: nil, screen: r.screen)
                d.log("\(item.id): none of \(labels) on the panel in \(Int(timeout)) s: \(q(whole.seen?.text))")
                return (savePanel(whole, item, name), nil, nil, at)
            }
            d.pause(0.5)
        }
    }

    private func savePanel(_ r: PanelRead, _ item: Item, _ name: String) -> PanelRead {
        let f = item.nextShot(name)
        let saved = d.savePNG(f, r.screen)
        d.log("\(item.id) \(name): \(q(r.seen?.text))")
        return PanelRead(screen: r.screen, seen: r.seen, file: saved ? f + ".png" : nil)
    }

    /// Taps a panel button found by OCR in its row. false when the label is not there.
    @discardableResult
    func tapPanelButton(_ label: String, _ row1: CGFloat, _ item: Item) -> Bool {
        let r = readPanel(row1, item, save: nil)
        guard let rect = r.seen?.word(label, in: d.panelButtonBand(row1: row1)) else {
            d.log("\(item.id): no \(label) button on the panel: \(q(r.seen?.text))")
            return false
        }
        d.point(rect.midX, rect.midY).tap()
        d.pause(1)
        d.log(String(format: "\(item.id): tapped %@ at %.1f, %.1f", label, rect.midX, rect.midY))
        return true
    }

    // MARK: Translate / Polish

    struct Attempt {
        /// The field after Insert.
        var output: String?
        /// Tap to the screenshot that showed the result's button.
        var seconds: Double?
        /// The result panel's OCR text (translation, back translation or change line).
        var panel: String?
        /// The busy label ("Translating") was on the panel at once.
        var busy: Bool?
        /// Why there is no output: a step the test judges itself (FAIL), not model output.
        var problem: String?
        /// The panel failed (Retry) or no result came: one retry.
        var transient = false
        var capped = false
        /// The action was tapped (a request went out).
        var tapped = false
    }

    /// One try: clear, type the draft (the flip rule for its code), check the field and the center's label, tap it,
    /// look for the busy label at once, wait for Insert, then tap Insert and read the field (insert false: Cancel).
    func attempt(_ item: Item, _ draft: Draft, center want: String, busy: String, n: Int, insert: Bool = true,
                 saveBusy: Bool = false) -> Attempt {
        var a = Attempt()
        d.clearField()
        if let code = draft.code {
            typeCode(code, item)
            d.type(": " + draft.text)
        } else {
            d.type(draft.text)
        }
        let typed = field()
        guard typed == draft.full else {
            a.problem = "draft#\(n) typed as \(q(typed)) want \(q(draft.full))"
            return a
        }
        let center = readSlot(.center, item)
        guard center.unreadable == nil, let label = center.text else {
            a.problem = "center#\(n) unreadable (\(center.unreadable ?? "no OCR text"), \(center.file))"
            return a
        }
        guard label == want else {
            a.problem = "center#\(n)=\(q(label)) want \(q(want))"
            return a
        }
        guard let row1 = d.rowOne() else {
            a.problem = "no keyboard before the tap"
            return a
        }
        guard send(item) else {
            a.capped = true
            return a
        }
        let t0 = Date()
        d.tapSlot(.center, settle: 0)
        a.tapped = true
        // The loading panel shows at once (act() sets it before the request); poll up to 1.5 s for its label, and
        // stop when a result button is already there.
        let busyEnd = Date().addingTimeInterval(1.5)
        repeat {
            let r = readPanel(row1, item, save: nil)
            guard let seen = r.seen else { break }
            let band = d.panelButtonBand(row1: row1)
            if seen.contains(busy) || seen.word("Insert", in: band) != nil || seen.word("Retry", in: band) != nil {
                a.busy = seen.contains(busy)
                if saveBusy { _ = savePanel(r, item, "busy") }
                break
            }
            a.busy = false
        } while Date() < busyEnd
        let w = waitPanel(row1, item, for: ["Insert", "Retry"], name: "result")
        a.panel = w.read.seen?.text
        guard let hit = w.label, let rect = w.rect else {
            a.problem = "no result in 30 s, panel \(q(a.panel))"
            a.transient = true
            return a
        }
        if hit == "Retry" {
            a.problem = "the panel failed: \(q(a.panel))"
            a.transient = true
            return a
        }
        a.seconds = w.at.timeIntervalSince(t0)  // only a result counts as a timing
        if !insert {
            tapPanelButton("Cancel", row1, item)
            return a
        }
        d.point(rect.midX, rect.midY).tap()
        d.pause(1.2)
        guard let out = field() else {
            a.problem = "field unreadable after Insert"
            return a
        }
        a.output = out
        return a
    }

    /// Up to two attempts (plan Task 2.3): the second when the first's output fails `passes` (checks.py RULES,
    /// repeated; checks.py decides) or its panel failed. Every output is `<group>#<n>` for checks.py.
    @discardableResult
    func tryAction(_ item: Item, _ draft: Draft, center: String, busy: String, needBusy: Bool,
                   group: String = "out", passes: (String) -> Bool) -> [Attempt] {
        var attempts: [Attempt] = []
        for n in 1...2 {
            let a = attempt(item, draft, center: center, busy: busy, n: n, saveBusy: needBusy)
            attempts.append(a)
            if a.capped {
                if n == 1 { item.skip("request cap") } else { item.note("retry=request cap") }
                break
            }
            if needBusy && a.tapped && a.busy == nil {
                item.markUnreadable("busy#\(n)=unreadable (no OCR of the panel right after the tap)")
            } else if let seen = a.busy {
                if needBusy {
                    item.require("busy#\(n)", seen, seen ? q(busy) : "no \(q(busy)) at once")
                } else {
                    item.note("busy#\(n)=\(seen ? "yes" : "no")")
                }
            }
            if let s = a.seconds { item.note(String(format: "seconds#%d=%.1f", n, s)) }
            if let p = a.problem {
                if a.transient && n == 1 {
                    item.note("try#1=\(p)")
                    resetKeyboard()
                    continue
                }
                item.require("try#\(n)", false, p)
                break
            }
            guard let out = a.output else { break }
            item.output(group, n, out)
            if passes(out) { break }
            item.note("retry: \(group)#\(n) fails the script rule")
        }
        return attempts
    }

    /// 6.8-11's Translate part, after the flip part (test1_68): a Korean draft, center Translate, Insert: Latin.
    func translate68(_ it: Item) {
        guard Self.network else {
            it.skip("no network key")  // the Translate part is the item's half: no PASS on the flip alone
            return
        }
        guard Self.fullAccess == true else {
            it.markUnreadable("translate: full access not on (\(Self.fullAccessHow))")
            return
        }
        context(korean: true, it)  // the flip just made the previous word English
        tryAction(it, Draft(code: nil, text: "오늘 정말 고마워 "), center: "Translate", busy: "Translating",
                  needBusy: false, passes: Rules.latin)
        resetKeyboard()
    }

    // MARK: Task 8.5 (feature plan), the network part

    func checks85network() {
        let ids = ["8.5-1", "8.5-3", "8.5-4", "8.5-5", "8.5-6", "8.5-7", "8.5-8", "8.5-9", "8.5-10"]
        if notReady(ids) || !networkReady(ids) { return }

        // Drafts end with a space: the bar offers no action while a word is being typed (Sprint 001 finding).
        var it = Item("8.5-1")
        context(korean: true, it)
        let ru = Draft(code: "ru", text: "누나 노트 고마워 누나 덕분에 살았다 ")
        let tries = tryAction(it, ru, center: "Translate", busy: "Translating", needBusy: true) {
            Rules.cyrillic($0) && !Rules.hangul($0) && !Rules.hasNoCase($0, "ru:") && $0.contains("спасла")
        }
        for (i, a) in tries.enumerated() {
            if a.tapped { it.note("back#\(i + 1)=\(a.panel.map { Rules.hangul($0) ? "hangul" : "none" } ?? "unreadable")") }
        }
        if tries.last?.output != nil {
            noteSlot(it, "undo-slot", readSlot(.center, it))
            d.tapSlot(.center)
            it.expect("undo", field(), ru.full)
        }
        var times = tries.compactMap { $0.seconds }
        finish(it)
        resetKeyboard()

        simple("8.5-3", Draft(code: "ja", text: "내일 시간 있어? 같이 밥 먹자 ㅋㅋ "), korean: true) {
            Rules.kanaOrKanji($0) && !Rules.hangul($0) && !Rules.hasNoCase($0, "lol")
        }
        simple("8.5-4", Draft(code: "es", text: "나 오늘 너무 피곤해 "), korean: true) {
            Rules.hasNoCase($0, "cansado") && !Rules.hasNoCase($0, "cansada") && !Rules.hangul($0)
        }
        simple("8.5-5", Draft(code: nil, text: "내일 3시에 봐 "), korean: true, passes: Rules.latin)
        simple("8.5-6", Draft(code: "ok", text: "내일 봐 "), korean: true, passes: Rules.latin)
        simple("8.5-7", Draft(code: "ko", text: "낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠 "), korean: true,
               center: "Polish", busy: "Polishing", needBusy: true) {
            Rules.hangul($0) && $0.contains("ㅋㅋ") && $0.contains("돼") && $0.contains("말해줘") && !Rules.hasNoCase($0, "ko:")
        }
        simple("8.5-8", Draft(code: "ko", text: "오늘 진짜 길었어\n\n낼 아침에 전화할게\n\n늦으면 미안 ㅠㅠ "), korean: true,
               center: "Polish", busy: "Polishing", needBusy: true) {
            Rules.hangul($0) && !Rules.hasNoCase($0, "ko:")
        }
        simple("8.5-9", Draft(code: nil, text: "me encanta el color de tu chaqueta, donde la conprastes? jaja "),
               korean: false, center: "Polish", busy: "Polishing") {
            Rules.hasNoCase($0, "color") && Rules.hasWord($0, "compraste") && Rules.hasNoCase($0, "jaja")
                && !Rules.hasNoCase($0, "colour") && !Rules.hasNoCase($0, "conprastes")
        }

        // 8.5-10: seconds from tap to Insert for 8.5-1, two tries (a second, Cancel instead of Insert, if 8.5-1 had one).
        it = Item("8.5-10")
        if times.count < 2 {
            context(korean: true, it)
            let a = attempt(it, ru, center: "Translate", busy: "Translating", n: 2, insert: false)
            if a.capped { it.note("try#2=request cap") }
            if let s = a.seconds { times.append(s) }
            if let p = a.problem { it.note("try#2=\(p)") }
            resetKeyboard()
        }
        if times.count < 2 {
            it.markUnreadable("\(times.count) of 2 timings")
        }
        if !times.isEmpty {
            let list = times.enumerated().map { String(format: "try%d=%.1fs", $0.offset + 1, $0.element) }
            it.note(list.joined(separator: " ") + " (tap to Insert shown; OCR poll every 0.5 s)")
        }
        finish(it, record: true)
    }

    /// One draft, one action, the Insert checked by checks.py; the panel's text is kept as `shown#n` (RECORD part:
    /// back translation or change line).
    private func simple(_ id: String, _ draft: Draft, korean: Bool, center: String = "Translate",
                        busy: String = "Translating", needBusy: Bool = false, passes: (String) -> Bool) {
        let it = Item(id)
        context(korean: korean, it)
        let tries = tryAction(it, draft, center: center, busy: busy, needBusy: needBusy, passes: passes)
        for (i, a) in tries.enumerated() {
            if a.tapped { it.note("shown#\(i + 1)=\(q(a.panel))") }
        }
        finish(it)
        resetKeyboard()
    }

    // MARK: Read clipboard and Allow Paste (plan Task 2.2 step 2)

    struct ClipRead {
        let label: String?
        let seen: Seen?
        let rect: CGRect?
        let row1: CGFloat
        var text: String { seen?.text ?? "" }

        func contains(_ phrase: String) -> Bool { seen?.contains(phrase) ?? false }
    }

    /// Read clipboard. With `text` (the host): the keyboard goes down, the test runner sets the clipboard, and the
    /// keyboard comes back on the empty field, so the bar looks at the clipboard (viewWillAppear). Without (the
    /// container app): its Copy button has set it. Taps the center's `Read clipboard` (the protly key when the
    /// center does not offer it, noted), answers Allow Paste and waits for one of `labels`. nil: it did not start.
    func readClipboard(_ item: Item, _ text: String?, waitFor labels: [String], sends: Bool, name: String = "clipboard",
                       markTimeout: Bool = true, probe: ((String) -> Void)? = nil) -> ClipRead? {
        let inHost = text != nil
        if let text {
            d.clearField()
            d.dismissKeyboard()
            d.pause(1)
            UIPasteboard.general.string = text
            d.focusField()
            d.waitOutStandIn()
        }
        d.pause(0.8)
        guard let row1 = d.rowOne() else {
            item.markUnreadable("\(name): no keyboard")
            return nil
        }
        let center = readSlot(.center, item)
        let offered = center.text == "Read clipboard"
        if inHost {
            // The host brings the keyboard back on an empty field, so the bar must offer it (refreshField).
            item.require("\(name)-center", offered, q(center.text))
        } else {
            item.note("\(name)-center=\(q(center.text))")
        }
        if sends && !send(item) {
            item.skip("request cap")
            return nil
        }
        if offered {
            d.tapSlot(.center, settle: 0)
        } else {
            d.tapKey(.protlyKey)
            item.note("\(name)=protly key")
        }
        if let probe {
            d.pause(1.5)
            d.savePNG("probe-paste")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            try? d.app.debugDescription.write(to: d.out.appendingPathComponent("tree-paste-app.txt"), atomically: true, encoding: .utf8)
            try? springboard.debugDescription.write(to: d.out.appendingPathComponent("tree-paste-springboard.txt"),
                                                    atomically: true, encoding: .utf8)
            probe("paste prompt: app alerts \(d.app.alerts.count), springboard alerts \(springboard.alerts.count), "
                  + "Allow Paste in app \(d.app.buttons["Allow Paste"].exists), in springboard \(springboard.buttons["Allow Paste"].exists)")
        }
        let how = allowPaste(trigger: inHost)
        item.note("\(name)-paste=\(q(how))")
        probe?("allow paste: \(how)")
        d.append("allow paste (\(item.id) \(name)): \(how)", to: "network.txt")
        let w = waitPanel(row1, item, for: labels, timeout: sends ? 30 : 10, name: name)
        if w.label == nil && markTimeout { item.markUnreadable("\(name): none of \(labels) on the panel, \(q(w.read.seen?.text))") }
        return ClipRead(label: w.label, seen: w.read.seen, rect: w.rect, row1: row1)
    }

    /// The Allow Paste prompt of a clipboard read: an interruption monitor first (it runs on the next interaction,
    /// a tap on the host's empty background), then the button itself in the app under test or SpringBoard.
    func allowPaste(trigger: Bool, timeout: TimeInterval = 6) -> String {
        let before = PasteMonitor.fired
        d.pause(1)
        if trigger { d.point(d.width / 2, 150).tap() }  // the host's background, away from its field and buttons
        if PasteMonitor.fired > before { return "interruption monitor" }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for (where_, a) in [("app", d.app), ("springboard", springboard)] {
                let b = a.buttons["Allow Paste"]
                if b.exists {
                    b.tap()
                    let gone = b.waitForNonExistence(timeout: 3)
                    return "tapped Allow Paste in the \(where_)" + (gone ? "" : ", but the prompt stayed")
                }
            }
            if PasteMonitor.fired > before { return "interruption monitor" }
            d.pause(0.5)
        } while Date() < end
        return "no Allow Paste prompt in \(Int(timeout)) s"
    }

    func registerPasteMonitor() {
        _ = d.test.addUIInterruptionMonitor(withDescription: "Allow Paste") { alert in
            MainActor.assumeIsolated {
                let b = alert.buttons["Allow Paste"]
                guard b.exists else { return false }
                b.tap()
                PasteMonitor.fired += 1
                return true
            }
        }
    }

    // MARK: Task 7.7 (feature plan): the about-me note

    func checks77() {
        let ids = (1...6).map { "7.7-\($0)" }
        if notReady(ids) { return }
        guard accessReady(ids.filter { $0 != "7.7-6" }) else {
            write("7.7-6", "SKIP", "needs a phone reinstall")
            return
        }
        registerPasteMonitor()
        let count = Self.testNote.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count

        var it = Item("7.7-1")
        inApp(it) { a in self.saveNote(it, a, count: count, tag: "") }
        finish(it)

        var times: [Double] = []
        it = Item("7.7-2")
        if Self.network {
            context(korean: true, it)
            let tries = tryAction(it, Self.kiln, center: "Translate", busy: "Translating", needBusy: false,
                                  passes: Rules.aboutMe)
            if let s = tries.compactMap({ $0.seconds }).first { times.append(s) }
            finish(it)
            resetKeyboard()
        } else {
            write("7.7-2", "SKIP", "no network key")
        }

        it = Item("7.7-3")
        if Self.network {
            readEnglish(it)
            if let r = readClipboard(it, "protly about me v1\ntest", waitFor: ["Save"], sends: false, name: "test-note") {
                it.require("four", r.contains("(4 characters)"), q(r.text))
                if !tapPanelButton("Cancel", r.row1, it) { it.markUnreadable("no Cancel on the confirm panel") }
            }
            resetKeyboard()
            context(korean: true, it)
            let tries = tryAction(it, Self.kiln, center: "Translate", busy: "Translating", needBusy: false,
                                  passes: Rules.aboutMe)
            if let s = tries.compactMap({ $0.seconds }).first { times.append(s) }
            finish(it)
            resetKeyboard()
        } else {
            write("7.7-3", "SKIP", "no network key")
        }

        // 7.7-4: seconds from tap to Insert for Translate with the note: 7.7-2 and 7.7-3's repeat of it.
        it = Item("7.7-4")
        if !Self.network {
            write("7.7-4", "SKIP", "no network key")
        } else {
            if times.count < 2 { it.markUnreadable("\(times.count) of 2 timings") }
            let list = times.enumerated().map { String(format: "try%d=%.1fs", $0.offset + 1, $0.element) }
            it.note(list.joined(separator: " ") + " (7.7-2 and 7.7-3's repeat; tap to Insert shown, OCR poll every 0.5 s)")
            finish(it, record: true)
        }

        it = Item("7.7-5")
        inApp(it) { a in
            let field = self.appInput(a, placeholder: "Who you are, in a few facts", index: 0)
            it.note("clear=\(q(self.clearAboutMe(a, field, count: count)))")
            if let c = self.counter(a) {
                it.require("counter-clear", c == 0, "\(c) want 0")
            } else {
                it.markUnreadable("counter-clear=unreadable")
            }
            self.copyForKeyboard(a, it, "-clear")
            self.confirmInApp(it, a, confirm: ["Clear your About me note"], saved: ["About me cleared"], tag: "-clear")
            self.saveNote(it, a, count: count, tag: "-again")
        }
        finish(it)

        write("7.7-6", "SKIP", "needs a phone reinstall")
        d.append("requests: \(Self.requests) of at most \(Self.requestCap)", to: "network.txt")
    }

    /// 7.7-3's first part: a friend's English message, empty field, Read clipboard: Korean on the panel (one retry).
    private func readEnglish(_ it: Item) {
        for n in 1...2 {
            guard let r = readClipboard(it, "Can you send me the photos from yesterday?", waitFor: ["Done", "Retry"],
                                        sends: true, name: "read", markTimeout: false) else { return }
            if r.label == "Retry" || r.label == nil {
                it.note("read#\(n) failed: \(q(r.text))")
                resetKeyboard()
                if n == 2 { it.require("read", false, "no translation in two tries") }
                continue
            }
            it.output("panel", n, r.text)
            if let rect = r.rect {
                d.point(rect.midX, rect.midY).tap()  // Done
                d.pause(1)
            }
            resetKeyboard()
            if Rules.hangul(r.text) { return }
            it.note("retry: panel#\(n) fails the script rule")
        }
    }

    /// Runs `body` in the container app (ProtlyCIApp), then brings the host back with Protly.
    private func inApp(_ item: Item, _ body: (Driver) -> Void) {
        guard let a = try? Driver(test: d.test, bundleIdentifier: Self.appID) else {
            item.markUnreadable("no driver for \(Self.appID)")
            return
        }
        a.strict = false
        a.keyPause = d.keyPause
        // The Form's screen is not the host's solid color: row 1 comes from the host's last measurement.
        a.fixedRow1 = Driver.lastRow1 ?? 564
        a.launch()
        let host = d
        d = a
        body(a)
        for p in a.takeProblems() { item.markUnreadable("app problem=\(q(p))") }
        a.savePNG("c-\(item.id)-app")
        a.app.terminate()
        d = host
        d.launch()
        d.ensureProtly()
    }

    /// 7.7-1 (and the redo in 7.7-5): paste the note into About me, the counter, Copy for the keyboard, then Read
    /// clipboard in the app's Test field: the confirm panel with the counter's number, Save, Done.
    private func saveNote(_ it: Item, _ a: Driver, count: Int, tag: String) {
        let field = appInput(a, placeholder: "Who you are, in a few facts", index: 0)
        guard field.waitForExistence(timeout: 5) else {
            it.markUnreadable("about-me\(tag)=no field")
            return
        }
        UIPasteboard.general.string = Self.testNote
        it.note("paste\(tag)=\(q(paste(a, into: field)))")
        guard let c = counter(a) else {
            it.markUnreadable("counter\(tag)=unreadable")
            return
        }
        it.require("counter\(tag)", c == count, "\(c) want \(count)")
        copyForKeyboard(a, it, tag)
        confirmInApp(it, a, confirm: ["Save as your About me note", "(\(c) characters)"],
                     saved: ["About me saved", "\(c) characters"], tag: tag)
    }

    /// In the app's Test field: Read clipboard, the confirm panel's text, Save (after AboutMe.saveDelay), the
    /// notice, Done, and the bar back without panel text.
    private func confirmInApp(_ it: Item, _ a: Driver, confirm: [String], saved: [String], tag: String) {
        let test = appInput(a, placeholder: "Type here", index: 1)
        guard test.waitForExistence(timeout: 3) else {
            it.markUnreadable("test-field\(tag)=missing")
            return
        }
        bringAboveKeyboard(a, test)
        test.tap()
        a.pause(1)
        a.fieldOverride = test
        a.waitOutStandIn()
        let board = a.current()
        if board == .english || board == .emoji { _ = a.pick(.protly) }
        guard let r = readClipboard(it, nil, waitFor: ["Save"], sends: false, name: "confirm\(tag)"),
              r.label == "Save", let save = r.rect else { return }
        for phrase in confirm { it.require("confirm\(tag)", r.contains(phrase), "\(q(phrase)) in \(q(r.text))") }
        a.pause(0.8)  // Save is inert for AboutMe.saveDelay (0.5 s) after the panel shows
        a.point(save.midX, save.midY).tap()
        let w = waitPanel(r.row1, it, for: ["Done"], timeout: 5, name: "saved\(tag)")
        let notice = w.read.seen?.text ?? ""
        for phrase in saved { it.require("saved\(tag)", w.read.seen?.contains(phrase) ?? false, "\(q(phrase)) in \(q(notice))") }
        guard let done = w.rect else {
            it.markUnreadable("saved\(tag)=no Done")
            return
        }
        a.point(done.midX, done.midY).tap()
        a.pause(1)
        let after = readPanel(r.row1, it, save: "after\(tag)")
        let band = a.panelButtonBand(row1: r.row1)
        let leftover = after.seen.map { seen in
            seen.contains("About me") || ["Done", "Save", "Cancel"].contains { seen.word($0, in: band) != nil }
        } ?? true
        it.require("bar\(tag)", !leftover, "keys back, panel region \(q(after.seen?.text))")
        noteSlot(it, "bar-center\(tag)", readSlot(.center, it))
    }

    /// A text input of the container app by its placeholder; else the index-th text input (logged).
    func appInput(_ a: Driver, placeholder: String, index: Int) -> XCUIElement {
        let byPlaceholder = a.app.descendants(matching: .any)
            .matching(NSPredicate(format: "placeholderValue == %@", placeholder)).firstMatch
        if byPlaceholder.waitForExistence(timeout: 3) { return byPlaceholder }
        a.dumpOnce("app-inputs", a.app)
        a.log("no input with the placeholder \(q(placeholder)): taking text input \(index)")
        let types = [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue]
        return a.app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType IN %@", types as NSArray)).element(boundBy: index)
    }

    /// The About me counter, `N / 1000`.
    func counter(_ a: Driver) -> Int? {
        let t = a.app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " / 1000")).firstMatch
        guard t.waitForExistence(timeout: 2) else { return nil }
        return Int(t.label.components(separatedBy: " / ").first?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    /// An in-app paste from the edit menu: no Allow Paste prompt, and no typeText (it fails with Protly active).
    private func paste(_ a: Driver, into field: XCUIElement) -> String {
        field.tap()
        a.pause(1)
        bringAboveKeyboard(a, field)
        let ways: [(String, () -> Void)] = [("tap", { field.tap() }), ("long press", { field.press(forDuration: 1.2) })]
        for (how, act) in ways {
            act()
            a.pause(0.8)
            if tapMenu(a, "Paste") { return "\(how), Paste" }
        }
        a.dumpOnce("app-edit-menu", a.app)
        return "no Paste in the edit menu"
    }

    /// Empties the About me field: Select All, then Cut (or delete on Protly).
    private func clearAboutMe(_ a: Driver, _ field: XCUIElement, count: Int) -> String {
        field.tap()
        a.pause(0.8)
        bringAboveKeyboard(a, field)
        field.press(forDuration: 1.2)
        a.pause(0.8)
        if tapMenu(a, "Select All") {
            if tapMenu(a, "Cut") { return "Select All, Cut" }
            a.tapKey(.delete)  // typing delete over a selection removes it
            return "Select All, delete key"
        }
        a.dumpOnce("app-select-menu", a.app)
        for _ in 0..<(count + 5) { a.tapKey(.delete) }
        return "no Select All: \(count + 5) delete taps"
    }

    /// Drags the container app's Form until `e` sits between the navigation bar and the keyboard's top: with About
    /// me focused the keyboard covers the Form's lower part, and a tap there would land on Protly's keys.
    private func bringAboveKeyboard(_ a: Driver, _ e: XCUIElement) {
        let keyboardTop = (a.fixedRow1 ?? 564) - Geo.band - 4
        for _ in 0..<5 {
            let f = e.frame
            if f.height > 0, f.maxY < keyboardTop, f.minY > 100 { return }
            let up = f.maxY >= keyboardTop  // the content moves up
            a.point(a.width / 2, up ? 420 : 220).press(forDuration: 0.1, thenDragTo: a.point(a.width / 2, up ? 300 : 340))
            a.pause(0.8)
        }
        a.log("still not between the bar and the keyboard: \(e.frame)")
    }

    private func tapMenu(_ a: Driver, _ name: String) -> Bool {
        for e in [a.app.menuItems[name], a.app.buttons[name]] where e.waitForExistence(timeout: 1.5) {
            e.tap()
            a.pause(0.8)
            return true
        }
        return false
    }

    private func copyForKeyboard(_ a: Driver, _ it: Item, _ tag: String) {
        let b = a.app.buttons["Copy for the keyboard"]
        guard b.waitForExistence(timeout: 3) else {
            it.markUnreadable("copy\(tag)=no Copy for the keyboard button")
            return
        }
        bringAboveKeyboard(a, b)
        b.tap()
        a.pause(0.8)
        it.require("copied\(tag)", a.app.buttons["Copied"].waitForExistence(timeout: 2), "\"Copied\"")
    }
}

/// A draft: a language code typed with the flip rule, then ": " and the text (which ends with a space).
struct Draft {
    let code: String?
    let text: String

    var full: String { (code.map { $0 + ": " } ?? "") + text }
}

/// Times the interruption monitor answered an Allow Paste prompt.
enum PasteMonitor {
    static var fired = 0
}

/// checks.py RULES, repeated only to decide on the one retry: checks.py's verdict is the reported one.
enum Rules {
    private static func scalars(_ s: String) -> String.UnicodeScalarView { s.precomposedStringWithCanonicalMapping.unicodeScalars }

    static func cyrillic(_ s: String) -> Bool { scalars(s).contains { (0x0400...0x04FF).contains($0.value) } }

    static func hangul(_ s: String) -> Bool {
        scalars(s).contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    static func kanaOrKanji(_ s: String) -> Bool {
        scalars(s).contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    static func latin(_ s: String) -> Bool {
        scalars(s).contains { $0.isASCII && $0.properties.isAlphabetic } && !hangul(s)
    }

    static func hasNoCase(_ s: String, _ sub: String) -> Bool { s.range(of: sub, options: .caseInsensitive) != nil }

    /// Case-insensitive, whole word.
    static func hasWord(_ s: String, _ word: String) -> Bool {
        s.range(of: "(?<!\\w)" + NSRegularExpression.escapedPattern(for: word) + "(?!\\w)",
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func aboutMe(_ s: String) -> Bool {
        s.contains("Moonbeam Kiln") && !hasNoCase(s, "pottery") && !hasNoCase(s, "Victoria") && !hangul(s)
    }
}
