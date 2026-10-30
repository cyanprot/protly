import ProtlyCore
import UIKit
import XCTest

/// The phone checks of docs/plans/2026-10-30-sim-phone-checks.md, Sprint 001 (no network): checklist items of the
/// feature plan's Tasks 6.8 and 8.5, the flip-over-whitespace rule (997f108), memory and the app icon.
///
/// Each item appends `CHECK <id> PASS|FAIL|RECORD|SKIP|PENDING <evidence>` to $SHOTS_DIR/checks.txt and saves
/// c-<id>.png; checks.py resolves PENDING and assembles the report. An item never fails the test itself (a FAIL on
/// keyboard behaviour is a finding, and the job still measures the layout). Learned words carry over between
/// methods, so the methods are numbered: XCTest runs them alphabetically, after KeyboardShotsUITests.
final class PhoneChecksUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Plan Task 1.0. Only with PROBE=1 (run-shots.sh passes it on a `[probe]` commit).
    @MainActor
    func test0_probe() throws {
        guard ProcessInfo.processInfo.environment["PROBE"] == "1" else {
            throw XCTSkip("the probe runs only with PROBE=1")
        }
        try PhoneRun(test: self, name: "test0_probe").probe()
    }

    @MainActor
    func test1_68() throws {
        try PhoneRun(test: self, name: "test1_68").checks68()
    }

    @MainActor
    func test2_ws() throws {
        try PhoneRun(test: self, name: "test2_ws").checksWhitespace()
    }

    @MainActor
    func test3_85offline() throws {
        try PhoneRun(test: self, name: "test3_85offline").checks85()
    }

    @MainActor
    func test4_memory() throws {
        try PhoneRun(test: self, name: "test4_memory").memory()
    }

    @MainActor
    func test5_icon() throws {
        try PhoneRun(test: self, name: "test5_icon", launch: false).icon()
    }
}

/// A string as checks.py reads it back: in double quotes, with \\, \" and \n escaped. nil is `<unreadable>`.
func q(_ s: String?) -> String {
    guard let s else { return "<unreadable>" }
    var r = "\""
    for ch in s {
        switch ch {
        case "\\": r += "\\\\"
        case "\"": r += "\\\""
        case "\n": r += "\\n"
        default: r.append(ch)
        }
    }
    return r + "\""
}

func hasHangul(_ s: String) -> Bool { s.contains { Typing.isHangul($0) } }

func hasLatinLetter(_ s: String) -> Bool { s.contains { $0.isASCII && $0.isLetter } }

/// One checklist item's evidence while it runs.
final class Item {
    let id: String
    private var failed = false
    private var unreadable = false
    /// Vision failed its self-test in this run: label readings are crops for the tower (plan Task 1.2 step 3).
    private var ocrMissing = false
    private var notes: [String] = []
    private var shots = 0

    init(_ id: String) {
        self.id = id
    }

    func note(_ s: String) {
        notes.append(s)
    }

    /// `got` must equal `want` (Swift compares canonically, so NFC and NFD Hangul are equal).
    func expect(_ name: String, _ got: String?, _ want: String) {
        guard let got else {
            markUnreadable("\(name)=unreadable")
            return
        }
        if got == want {
            notes.append("\(name)=\(q(got))")
        } else {
            failed = true
            notes.append("\(name)=\(q(got)) want \(q(want))")
        }
    }

    func require(_ name: String, _ ok: Bool, _ detail: String) {
        if !ok { failed = true }
        notes.append("\(name)=\(detail)" + (ok ? "" : " (not as expected)"))
    }

    func markUnreadable(_ why: String) {
        unreadable = true
        notes.append(why)
    }

    func markOCRMissing(_ why: String) {
        ocrMissing = true
        notes.append(why)
    }

    func nextShot(_ what: String) -> String {
        shots += 1
        return "c-\(id)-\(shots)-\(what)"
    }

    func status(record: Bool) -> String {
        if unreadable || failed { return "FAIL" }
        return record || ocrMissing ? "RECORD" : "PASS"
    }

    var evidence: String {
        (unreadable ? "unreadable: " : "") + notes.joined(separator: " ")
    }
}

/// What a bar slot showed: OCR text (nil when Vision failed or is unusable), ink pixels (-1: no keyboard found), and
/// the saved screenshot.
struct SlotRead {
    let text: String?
    let ink: Int
    let file: String
}

@MainActor
final class PhoneRun {
    let d: Driver
    let reader: Reader
    private let ready: Bool
    /// Fewer ink pixels than this in a slot = nothing drawn there. A word is thousands at 3x.
    static let inkEmpty = 40

    init(test: XCTestCase, name: String, launch: Bool = true) throws {
        let driver = try Driver(test: test)
        driver.strict = false
        driver.keyPause = 0.35
        let reader = Reader(driver: driver)
        driver.log("== PhoneChecksUITests.\(name)")
        reader.selfTest()
        var ok = false
        if launch {
            driver.launch()
            ok = driver.ensureProtly()
        }
        d = driver
        self.reader = reader
        ready = ok
    }

    // MARK: Recording

    func write(_ id: String, _ status: String, _ evidence: String) {
        let line = "CHECK \(id) \(status) \(evidence)"
        d.append(line, to: "checks.txt")
        d.log(line)
        d.savePNG("c-\(id)")
    }

    func finish(_ item: Item, record: Bool = false) {
        for p in d.takeProblems() { item.note("problem=\(q(p))") }
        write(item.id, item.status(record: record), item.evidence)
    }

    /// Every ID of a group FAIL when Protly could not be brought up (the CI could not check them).
    func notReady(_ ids: [String]) -> Bool {
        guard !ready else { return false }
        let why = d.takeProblems().joined(separator: "; ")
        for id in ids { write(id, "FAIL", "unreadable: protly keyboard not reached \(q(why))") }
        return true
    }

    // MARK: Reading

    func field() -> String? {
        d.fieldText()
    }

    /// Screenshot (saved), then OCR and ink of one slot.
    func readSlot(_ slot: Slot, _ item: Item) -> SlotRead {
        d.pause(0.6)  // the bar follows the last key
        let screen = XCUIScreen.main.screenshot()
        let file = item.nextShot(slot.name)
        d.savePNG(file, screen)
        guard let shot = d.screenshot(screen), let row1 = d.rowOne(shot) else {
            d.log("\(item.id): no keyboard in \(file)")
            return SlotRead(text: nil, ink: -1, file: file + ".png")
        }
        let rect = d.slotRect(slot, row1: row1)
        let ink = shot.ink(in: rect, background: CGPoint(x: rect.midX, y: rect.minY + 1))
        var text: String?
        if reader.works, let lines = reader.text(in: rect, of: screen, points: d.width, label: "\(item.id) \(slot.name)") {
            text = Self.clean(lines.joined(separator: " "))
        }
        return SlotRead(text: text, ink: ink, file: file + ".png")
    }

    /// OCR text without the flip's curly quotes around it.
    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}\"'\u{2018}\u{2019}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The slot's text must pass `ok`; a missing reading is FAIL unreadable (RECORD with the crop when Vision is
    /// unusable in this run).
    func expectSlot(_ item: Item, _ name: String, _ r: SlotRead, _ want: String, _ ok: (String) -> Bool) {
        guard r.ink >= 0 else {
            item.markUnreadable("\(name)=no keyboard (\(r.file))")
            return
        }
        guard let text = r.text else {
            if reader.works {
                item.markUnreadable("\(name)=ocr error (\(r.file))")
            } else {
                item.markOCRMissing("\(name)=ocr-unavailable ink \(r.ink) crop \(r.file)")
            }
            return
        }
        item.require(name, ok(text), "\(q(text)) want \(want)")
    }

    func expectSlot(_ item: Item, _ name: String, _ r: SlotRead, equals want: String) {
        expectSlot(item, name, r, q(want)) { $0 == want }
    }

    /// Nothing in the slot: no OCR text and (near) no ink.
    func expectEmpty(_ item: Item, _ name: String, _ r: SlotRead) {
        guard r.ink >= 0 else {
            item.markUnreadable("\(name)=no keyboard (\(r.file))")
            return
        }
        if r.text == nil {
            if reader.works {
                item.markUnreadable("\(name)=ocr error (\(r.file))")
                return
            }
            item.markOCRMissing("\(name)=ocr-unavailable")
        }
        let empty = r.ink < Self.inkEmpty && (r.text ?? "").isEmpty
        item.require(name, empty, "ocr \(q(r.text)) ink \(r.ink) (\(r.file))")
    }

    /// Records what a slot shows (RECORD items); a missing reading is FAIL unreadable.
    func noteSlot(_ item: Item, _ name: String, _ r: SlotRead) {
        guard r.ink >= 0 else {
            item.markUnreadable("\(name)=no keyboard (\(r.file))")
            return
        }
        if let text = r.text {
            item.note("\(name)=\(q(text)) ink \(r.ink)")
        } else if reader.works {
            item.markUnreadable("\(name)=ocr error (\(r.file))")
        } else {
            item.markOCRMissing("\(name)=ocr-unavailable ink \(r.ink) crop \(r.file)")
        }
    }

    /// The flip rule: a language code that comes out as Hangul is flipped with the left slot before the colon.
    func typeCode(_ code: String, _ item: Item) {
        d.type(code)
        let f = field()
        if f == code {
            item.note("\(code)=latin")
        } else {
            d.tapSlot(.left)
            item.note("\(code)=\(q(f)) flip -> \(q(field()))")
        }
    }

    // MARK: Task 6.8 (feature plan) items 1-11

    func checks68() {
        let ids = (1...11).map { "6.8-\($0)" }
        if notReady(ids) { return }

        var it = Item("6.8-1")
        d.clearField()
        d.type("i dont think its ok teh.")
        it.expect("field", field(), "i dont think its ok teh.")
        d.clearField()
        d.type("teh")
        expectSlot(it, "right", readSlot(.right, it), equals: "the")
        d.tapSlot(.right)
        it.expect("after-tap", field(), "the ")
        finish(it)

        it = Item("6.8-2")
        d.clearField()
        d.type("recieve")
        expectSlot(it, "right", readSlot(.right, it), equals: "receive")
        d.type(".")
        it.expect("field", field(), "recieve.")
        finish(it)

        it = Item("6.8-3")
        d.clearField()
        d.type("tomo")
        expectSlot(it, "right", readSlot(.right, it), equals: "tomorrow")
        d.tapSlot(.right)
        it.expect("after-tap", field(), "tomorrow ")
        finish(it)

        it = Item("6.8-4")
        d.clearField()
        d.type("안녀")
        expectSlot(it, "right", readSlot(.right, it), "starts with \(q("안녕"))") { $0.hasPrefix("안녕") }
        d.clearField()
        d.type("안녕ㅎ")
        it.note("typed=\(q(field()))")
        d.tapSlot(.right)
        it.expect("after-tap", field(), "안녕하세요 ")
        finish(it)

        it = Item("6.8-5")
        d.clearField()
        d.type("omw")
        noteSlot(it, "right", readSlot(.right, it))
        d.type(" ")
        it.note("after-space=\(q(field()))")
        finish(it, record: true)

        write("6.8-6", "SKIP", "no contacts in the simulator")

        it = Item("6.8-7")
        for phrase in ["걍 가자", "걔 진짜 웃겨", "얘 뭐야", "꽤 좋다", "I need to get rid of it"] {
            d.clearField()
            d.type(phrase + " ")  // the space ends the last word, as sending would
            it.expect("field", field(), phrase + " ")
        }
        finish(it)

        it = Item("6.8-8")
        d.clearField()
        d.type("wyd")
        it.expect("typed", field(), "죵")
        d.tapSlot(.left)
        it.expect("after-flip", field(), "wyd")
        d.type(" ")
        d.clearField()
        d.type("wyd ")
        it.expect("again", field(), "wyd ")
        finish(it)

        // 6.8-11 before the relaunch: the flip part only (Translate is sprint 002's).
        it = Item("6.8-11")
        d.clearField()
        d.type("내일 봐")
        noteSlot(it, "left", readSlot(.left, it))
        d.tapSlot(.left)
        let other = KeyEncoder.keys(forHangul: "봐").map { Dubeolsik.latin($0) } ?? "?"
        it.expect("after-flip", field(), "내일 " + other)
        finish(it)

        // 6.8-9: the learned word survives a new host process; checks.py compares the keyboard pids at the marks.
        d.clearField()
        d.mark("relaunch-before")
        d.app.terminate()
        d.pause(2)
        d.launch()
        if d.ensureProtly() {
            d.mark("relaunch-after")
            d.clearField()
            d.type("wyd ")
            write("6.8-9", "PENDING", "field=\(q(field()))")
        } else {
            write("6.8-9", "FAIL", "unreadable: protly keyboard not reached after the relaunch")
        }
        d.clearField()
    }

    // MARK: Flip over whitespace (997f108)

    func checksWhitespace() {
        if notReady(["ws-1", "ws-2", "ws-3"]) { return }

        var it = Item("ws-1")
        d.clearField()
        d.type("hello ")
        let left = readSlot(.left, it)
        expectSlot(it, "left", left, "Hangul") { hasHangul($0) }
        d.tapSlot(.left)
        let f = field()
        it.note("after-tap=\(q(f))")
        if let f {
            it.require("korean-reading-plus-space", hasHangul(f) && !hasLatinLetter(f) && f.hasSuffix(" "), q(f))
        } else {
            it.markUnreadable("after-tap=unreadable")
        }
        finish(it)

        it = Item("ws-2")
        d.clearField()
        d.type("hello.")
        d.type(" ")
        it.note("field=\(q(field()))")
        expectEmpty(it, "left", readSlot(.left, it))
        finish(it)

        it = Item("ws-3")
        d.clearField()
        d.type("hello\n")
        it.note("field=\(q(field()))")
        expectEmpty(it, "left", readSlot(.left, it))
        finish(it)
        d.clearField()
    }

    // MARK: Task 8.5 (feature plan), the offline part

    func checks85() {
        if notReady(["8.5-1o", "8.5-2o", "8.5-6o", "8.5-7o", "8.5-8o", "8.5-9o"]) { return }

        // A draft's last word is still being typed until a space ends it, and the bar offers no action while a word
        // is typed (ProtlyBar / refreshField): the drafts end with a space, except 8.5-8o (cursor at the end).
        var it = Item("8.5-1o")
        d.clearField()
        typeCode("ru", it)
        d.type(": 누나 노트 고마워 누나 덕분에 살았다 ")
        it.note("field=\(q(field()))")
        expectSlot(it, "center", readSlot(.center, it), equals: "Translate")
        finish(it)

        it = Item("8.5-2o")
        d.clearField()
        d.type("ru")
        it.note("ru-again=\(q(field()))")
        d.clearField()
        typeCode("zh", it)
        d.type(": 안녕 ")
        it.note("taught=\(q(field()))")
        d.clearField()
        d.type("zh ")
        it.note("zh-space=\(q(field()))")
        finish(it, record: true)

        it = Item("8.5-6o")
        d.clearField()
        typeCode("ok", it)
        d.type(": 내일 봐 ")
        it.note("field=\(q(field()))")
        expectSlot(it, "center", readSlot(.center, it), equals: "Translate")
        finish(it)

        it = Item("8.5-7o")
        d.clearField()
        typeCode("ko", it)
        d.type(": 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠 ")
        it.note("field=\(q(field()))")
        expectSlot(it, "center", readSlot(.center, it), equals: "Polish")
        finish(it)

        it = Item("8.5-8o")
        d.clearField()
        typeCode("ko", it)
        d.type(": 오늘 진짜 길었어\n\n낼 아침에 전화할게\n\n늦으면 미안 ㅠㅠ")
        it.note("field=\(q(field()))")
        noteSlot(it, "center", readSlot(.center, it))
        finish(it, record: true)

        it = Item("8.5-9o")
        d.clearField()
        d.type("me encanta el color de tu chaqueta, donde la conprastes? jaja ")
        it.note("field=\(q(field()))")
        expectSlot(it, "center", readSlot(.center, it), equals: "Polish")
        finish(it)
        d.clearField()
    }

    // MARK: Memory (plan Task 1.4)

    /// 30 presentations between two marks; memsample.py samples the keyboard process meanwhile and checks.py turns
    /// the samples nearest the marks into 6.8-10.
    func memory() {
        if notReady(["6.8-10"]) { return }
        d.clearField()
        d.pause(3)  // a sample with the keyboard up before the start mark
        d.mark("mem-start")
        var shown = 0
        for i in 1...30 {
            d.dismissKeyboard()
            d.pause(1)
            if i == 1 { d.log("after the first dismiss: \(d.current().rawValue)") }
            if d.field.waitForExistence(timeout: 2) { d.field.tap() }
            if d.waitForKeyboard(timeout: 4) { shown += 1 }
            d.pause(1)
        }
        d.mark("mem-end")
        d.pause(3)  // and one after the end mark
        let problems = d.takeProblems()
        let extra = problems.isEmpty ? "" : " problems=\(q(problems.joined(separator: "; ")))"
        write("6.8-10", "PENDING", "presentations=\(shown)/30\(extra)")
    }

    // MARK: The app icon (plan Task 1.5)

    func icon() {
        XCUIDevice.shared.press(.home)
        d.pause(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Protly"]
        var page = 0
        while page < 6 && !(icon.exists && icon.isHittable) {
            springboard.swipeLeft()
            d.pause(1)
            page += 1
        }
        d.savePNG("c-icon-home")
        if icon.exists && icon.isHittable {
            let frame = icon.frame
            do {
                try icon.screenshot().pngRepresentation.write(to: d.out.appendingPathComponent("c-icon.png"))
            } catch {
                d.log("icon: could not write the crop: \(error)")
            }
            let f = String(format: "{%.1f,%.1f,%.1f,%.1f}", frame.minX, frame.minY, frame.width, frame.height)
            d.append("CHECK icon RECORD \(f) found on page \(page + 1) (c-icon.png, c-icon-home.png)", to: "checks.txt")
        } else {
            d.savePNG("c-icon")
            d.append("CHECK icon RECORD missing after \(page) swipes (c-icon-home.png)", to: "checks.txt")
        }
        d.log("icon: page \(page + 1), exists \(icon.exists)")
    }

    // MARK: Probe (plan Task 1.0)

    func probe() {
        let p = { (line: String) in self.d.append(line, to: "probe.txt") }
        p("vision languages (.accurate): \(reader.supportedLanguages())")
        p("vision self-test: works \(reader.works), hangul \(reader.readsHangul)")
        guard ready else {
            p("protly not reached: \(d.takeProblems())")
            return
        }

        d.clearField()
        d.type("hello ")
        d.pause(0.8)
        let screen = XCUIScreen.main.screenshot()
        d.savePNG("probe-hello", screen)
        if let shot = d.screenshot(screen), let row1 = d.rowOne(shot) {
            p(String(format: "row 1 top %.2f pt", row1))
            let bar = CGRect(x: 16, y: row1 - Geo.barBottom - Geo.barHeight - 2, width: d.width - 32, height: Geo.barHeight + 3)
            p("hello space, whole bar: \(reader.text(in: bar, of: screen, points: d.width, label: "probe bar") ?? ["<vision error>"])")
            for s in Slot.allCases {
                let r = d.slotRect(s, row1: row1)
                let ocr = reader.text(in: r, of: screen, points: d.width, label: "probe \(s.name)") ?? ["<vision error>"]
                p("hello space, \(s.name) \(r): \(ocr) ink \(shot.ink(in: r, background: CGPoint(x: r.midX, y: r.minY + 1)))")
            }
        } else {
            p("hello space: no keyboard in probe-hello.png")
        }

        d.clearField()
        d.type("안녕")
        d.pause(0.5)
        let fieldShot = XCUIScreen.main.screenshot()
        d.savePNG("probe-hangul", fieldShot)
        let frame = d.field.frame.insetBy(dx: -8, dy: -8)
        let ocr = reader.text(in: frame, of: fieldShot, points: d.width, label: "probe field") ?? ["<vision error>"]
        p("field 안녕: value \(q(field())), ocr of \(frame): \(ocr)")

        d.clearField()
        if let row1 = d.rowOne() {
            let (x, y) = d.position(of: .layer123, row1: row1)
            d.point(x, y).tap()
            d.pause(1)
            d.savePNG("probe-123")
            p(String(format: "123 layer: probe-123.png (123 key tapped at %.1f, %.1f)", x, y))
            d.point(x, y).tap()  // ABC
            d.pause(0.8)
        }
        for symbol in [":", "?", ",", ".", "!"] {
            d.clearField()
            d.type(symbol)
            p("symbol \(symbol) at its computed position: field \(q(field()))")
        }
        d.clearField()
        p("problems: \(d.takeProblems())")
    }
}
