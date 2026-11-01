import ProtlyCore
import UIKit
import XCTest

/// The phone checks of docs/plans/2026-10-30-sim-phone-checks.md. Sprint 001 (no network): checklist items of the
/// feature plan's Tasks 6.8 and 8.5, the flip-over-whitespace rule (997f108), memory and the app icon. Sprint 002
/// (NetworkChecks.swift): Full Access, Translate / Polish / Read clipboard with the CI key, and the container app's
/// about-me note (Tasks 6.8 item 11, 7.7 and 8.5).
///
/// Each item appends `CHECK <id> PASS|FAIL|RECORD|SKIP|PENDING <evidence>` to $SHOTS_DIR/checks.txt and saves
/// c-<id>.png; checks.py resolves PENDING and assembles the report. An item never fails the test itself (a FAIL on
/// keyboard behaviour is a finding, and the job still measures the layout). Learned words carry over between
/// methods, so the methods are numbered: XCTest runs them alphabetically, after KeyboardShotsUITests.
final class PhoneChecksUITests: XCTestCase {
    /// Seconds each method may run before XCTest stops it (run-shots.sh passes -test-timeouts-enabled YES; XCTest
    /// rounds up to whole minutes). Run 36 ran 71 minutes without a line: a method that hangs now ends, and the
    /// network groups stop starting items 2 minutes before theirs (PhoneRun.startGroup).
    static let allowance: [String: TimeInterval] = [
        "test0_access": 300, "test0_probe": 480, "test1_68": 900, "test2_ws": 300, "test3_85offline": 900,
        "test4_memory": 600, "test5_icon": 300, "test5a_web": 900, "test5b_menu": 420, "test5c_pad": 420,
        "test5d_card": 720, "test5e_bar": 600,
        "test6_85net": 1080, "test7_77": 1080,
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
        // name is "-[ProtlyCIUITests.PhoneChecksUITests test6_85net]".
        let method = name.split(separator: " ").last.map { String($0.dropLast()) } ?? ""
        executionTimeAllowance = Self.allowance[method] ?? 600
    }

    /// Full Access for Protly (plan Task 2.2): read in Settings, turned on there when off. Every later method that
    /// needs it (network, clipboard) reads the outcome. Runs first: "access" sorts before "probe".
    @MainActor
    func test0_access() throws {
        try PhoneRun(test: self, name: "test0_access", launch: false).fullAccess()
    }

    /// Plan Task 2.2 (Sprint 002's probe; Sprint 001's, Task 1.0, is in the notes and git history). Only with
    /// PROBE=1 (run-shots.sh passes it on a `[probe]` commit).
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

    /// typing-fixes 004 (TypingChecks.swift): the dark web composer (dark-1, ret-*), the edit menu (menu-*) and the
    /// space trackpad (pad-*), on the host's extra screens. Offline, so before the network groups.
    @MainActor
    func test5a_web() throws {
        try PhoneRun(test: self, name: "test5a_web").checksWeb()
    }

    @MainActor
    func test5b_menu() throws {
        try PhoneRun(test: self, name: "test5b_menu", arguments: ["-screen", "uikit"]).checksMenu()
    }

    @MainActor
    func test5c_pad() throws {
        try PhoneRun(test: self, name: "test5c_pad", arguments: ["-screen", "uikit"]).checksPad()
    }

    /// keyboard-ui 003 (CardChecks.swift): the strip and the result card from the CI stub's recorded streams, dark and
    /// light, the cancel and the memory during a stream. Offline (a marker draft never reaches the API), after Full Access.
    @MainActor
    func test5d_card() throws {
        try PhoneRun(test: self, name: "test5d_card", arguments: ["-fills", Stub.fills]).checksCard()
    }

    /// keyboard-ui 003: the bar's hit frames, the bar in light mode, a long target name at a large text size, and the
    /// container app's guide screen in both looks.
    @MainActor
    func test5e_bar() throws {
        try PhoneRun(test: self, name: "test5e_bar", arguments: ["-fills", PhoneRun.barFills.joined(separator: "|")])
            .checksBar()
    }

    /// After every offline group, so the requests and the about-me note change nothing they check.
    @MainActor
    func test6_85net() throws {
        try PhoneRun(test: self, name: "test6_85net").checks85network()
    }

    @MainActor
    func test7_77() throws {
        try PhoneRun(test: self, name: "test7_77").checks77()
    }
}

/// A string as checks.py reads it back: in double quotes, with \\, \" and \n escaped, and every other line break
/// (\r, U+0085, U+2028, U+2029) as \n too, so one CHECK stays one line. nil is `<unreadable>`.
func q(_ s: String?) -> String {
    guard let s else { return "<unreadable>" }
    var r = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\\": r += "\\\\"
        case "\"": r += "\\\""
        case "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}": r += "\\n"
        default: r.unicodeScalars.append(u)
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
    /// SKIP and why (`no network key`, `request cap`), unless something already failed.
    private var skipReason: String?
    /// The item holds model output for checks.py's script rules: PENDING unless the test saw a FAIL itself.
    private var pending = false

    init(_ id: String) {
        self.id = id
    }

    func note(_ s: String) {
        notes.append(s)
    }

    /// A field reading kept as evidence; an unreadable field makes the item FAIL unreadable, RECORD items too.
    func noteField(_ name: String, _ value: String?) {
        if let value {
            notes.append("\(name)=\(q(value))")
        } else {
            markUnreadable("\(name)=unreadable")
        }
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

    /// One try's model output as `<group>#<n>="..."`, which checks.py judges (plan Task 2.3).
    func output(_ group: String, _ n: Int, _ text: String) {
        pending = true
        notes.append("\(group)#\(n)=\(q(text))")
    }

    /// The readings are for checks.py to judge (CardChecks.swift): PENDING unless the test saw a FAIL itself.
    func markPending() {
        pending = true
    }

    func skip(_ why: String) {
        skipReason = why
    }

    var skipped: Bool { skipReason != nil }

    var hasFailed: Bool { failed || unreadable }

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
        if skipReason != nil { return "SKIP" }
        if pending { return "PENDING" }
        return record || ocrMissing ? "RECORD" : "PASS"
    }

    var evidence: String {
        if let skipReason, !(unreadable || failed) { return ([skipReason] + notes).joined(separator: " ") }
        return (unreadable ? "unreadable: " : "") + notes.joined(separator: " ")
    }
}

/// What a bar slot showed: OCR text (nil when Vision failed or is unusable), ink pixels, and the saved screenshot.
/// `unreadable` says why nothing could be read (no Protly keyboard on screen, the screenshot not saved).
struct SlotRead {
    let text: String?
    let ink: Int
    let file: String
    var unreadable: String?
}

@MainActor
final class PhoneRun {
    /// The driver of the app under test: the host, or the container app while a 7.7 step runs there (inApp).
    var d: Driver
    let reader: Reader
    let ready: Bool
    /// OCR_FALLBACK=1 (plan Task 1.2 step 3): when Vision fails its self-test, label checks RECORD the crop instead
    /// of FAIL. Off by default: run 8's probe showed Vision works in the UI test.
    private let ocrFallback = ProcessInfo.processInfo.environment["OCR_FALLBACK"] == "1"
    /// Fewer ink pixels than this in a slot = nothing drawn there. A word is thousands at 3x.
    static let inkEmpty = 40

    /// `arguments`: the host's launch arguments (`-screen uikit`, HostApp.swift).
    init(test: XCTestCase, name: String, launch: Bool = true, arguments: [String] = []) throws {
        let driver = try Driver(test: test)
        driver.strict = false
        driver.keyPause = 0.35
        let reader = Reader(driver: driver)
        driver.log("== PhoneChecksUITests.\(name)")
        driver.restoreLooks()  // an earlier method that stopped in light mode or at a large text size
        reader.selfTest()
        var ok = false
        if launch {
            driver.launch(arguments: arguments)
            ok = driver.ensureProtly()
        }
        d = driver
        self.reader = reader
        ready = ok
    }

    // MARK: Recording

    /// A line for an item that does not go through `finish` (SKIP, not ready, PENDING). Its c-<id>.png must exist, or
    /// the line is FAIL unreadable.
    func write(_ id: String, _ status: String, _ evidence: String) {
        var line = "CHECK \(id) \(status) \(evidence)"
        if !d.savePNG("c-\(id)") && status != "FAIL" && status != "SKIP" {
            line = "CHECK \(id) FAIL unreadable: c-\(id).png not written; \(status) \(evidence)"
        }
        d.append(line, to: "checks.txt")
        d.log(line)
    }

    /// `screen`: the screenshot that shows the item (CardChecks: the card at the moment it was read), else the screen now.
    func finish(_ item: Item, record: Bool = false, screen: XCUIScreenshot? = nil) {
        // A step that did not happen (no keyboard to type on, Clear left text, a slot tap without a keyboard) means
        // the evidence does not show what the item claims.
        for p in d.takeProblems() { item.markUnreadable("problem=\(q(p))") }
        if !d.savePNG("c-\(item.id)", screen) { item.markUnreadable("c-\(item.id).png not written") }
        let line = "CHECK \(item.id) \(item.status(record: record)) \(item.evidence)"
        d.append(line, to: "checks.txt")
        d.log(line)
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
    func readSlot(_ slot: Slot, _ item: Item, languages: [String] = Reader.languages) -> SlotRead {
        d.pause(0.6)  // the bar follows the last key
        let board = d.current()
        let screen = XCUIScreen.main.screenshot()
        let file = item.nextShot(slot.name)
        guard d.savePNG(file, screen) else {
            return SlotRead(text: nil, ink: -1, file: file + ".png", unreadable: "screenshot not written")
        }
        guard board == .protly, let shot = d.screenshot(screen), let row1 = d.rowOne(shot) else {
            d.log("\(item.id): no Protly keyboard in \(file) (\(board.rawValue))")
            return SlotRead(text: nil, ink: -1, file: file + ".png", unreadable: "no Protly keyboard (\(board.rawValue))")
        }
        let rect = d.slotRect(slot, row1: row1)
        let ink = shot.ink(in: rect, background: CGPoint(x: rect.midX, y: rect.minY + 1))
        var text: String?
        if reader.works, let lines = reader.text(in: rect, of: screen, points: d.width, label: "\(item.id) \(slot.name)",
                                                 languages: languages) {
            text = Self.clean(lines.joined(separator: " "))
        }
        return SlotRead(text: text, ink: ink, file: file + ".png")
    }

    /// OCR first; when it misses, the slot button's accessibility label, if the slot has ink (the keyboard's elements
    /// are in the host's tree: tree-06). Once keyboard-ui 001 dropped the quotes around the flip, Vision read the
    /// jamo-only "ㅗ디ㅣㅐ" as "-]T" (runs 49f47b2-62 and 394cf1a-66, also from contrast-stretched crops); the label is
    /// the string the slot draws. Both readings are noted.
    func labelFallback(_ slot: Slot, _ item: Item, _ first: SlotRead, _ ok: (String) -> Bool) -> SlotRead {
        guard first.unreadable == nil, !(first.text.map(ok) ?? false) else { return first }
        let label = slotLabel(slot)
        item.note("\(slot.name)-ocr=\(q(first.text)) \(slot.name)-label=\(q(label)) ink \(first.ink)")
        guard let label, ok(label), first.ink >= Self.inkEmpty else { return first }
        return SlotRead(text: label, ink: first.ink, file: first.file)
    }

    /// The label of the button whose center is in `slot`'s rect, among buttons with a Hangul label.
    func slotLabel(_ slot: Slot) -> String? {
        guard let row1 = d.rowOne() else { return nil }
        let rect = d.slotRect(slot, row1: row1)
        let hangul = NSPredicate(format: "label MATCHES %@", ".*[\\u1100-\\u11FF\\u3130-\\u318F\\uAC00-\\uD7A3].*")
        return d.app.buttons.matching(hangul).allElementsBoundByIndex
            .first { rect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }?
            .label
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
        if let why = r.unreadable {
            item.markUnreadable("\(name)=\(why) (\(r.file))")
            return
        }
        guard let text = r.text else {
            missingOCR(item, name, r)
            return
        }
        item.require(name, ok(text), "\(q(text)) want \(want)")
    }

    /// No OCR text: FAIL unreadable, or RECORD with the crop when Vision failed its self-test and OCR_FALLBACK=1.
    func missingOCR(_ item: Item, _ name: String, _ r: SlotRead) {
        if !reader.works && ocrFallback {
            item.markOCRMissing("\(name)=ocr-unavailable ink \(r.ink) crop \(r.file)")
        } else {
            item.markUnreadable("\(name)=ocr \(reader.works ? "error" : "self-test failed") (\(r.file))")
        }
    }

    func expectSlot(_ item: Item, _ name: String, _ r: SlotRead, equals want: String) {
        expectSlot(item, name, r, q(want)) { $0 == want }
    }

    /// Nothing in the slot: no OCR text and (near) no ink.
    func expectEmpty(_ item: Item, _ name: String, _ r: SlotRead) {
        if let why = r.unreadable {
            item.markUnreadable("\(name)=\(why) (\(r.file))")
            return
        }
        if r.text == nil {
            missingOCR(item, name, r)
            if reader.works || !ocrFallback { return }
        }
        let empty = r.ink < Self.inkEmpty && (r.text ?? "").isEmpty
        item.require(name, empty, "ocr \(q(r.text)) ink \(r.ink) (\(r.file))")
    }

    /// Records what a slot shows (RECORD items); a missing reading is FAIL unreadable.
    func noteSlot(_ item: Item, _ name: String, _ r: SlotRead) {
        if let why = r.unreadable {
            item.markUnreadable("\(name)=\(why) (\(r.file))")
        } else if let text = r.text {
            item.note("\(name)=\(q(text)) ink \(r.ink)")
        } else {
            missingOCR(item, name, r)
        }
    }

    /// The flip rule: a language code that comes out as Hangul is flipped with the left slot before the colon.
    func typeCode(_ code: String, _ item: Item) {
        d.type(code)
        guard let f = field() else {
            item.markUnreadable("\(code)=unreadable")
            return
        }
        if f == code {
            item.note("\(code)=latin")
        } else {
            item.note("\(code)=\(q(f)) flip")
            d.tapSlot(.left)
            item.expect("\(code)-after-flip", field(), code)
        }
    }

    /// Sets the language of "the previous word" (the keyboard keeps it across messages): commits one word in that
    /// language, flipped with the left slot if it came out in the other one, then clears the field. The checklist's
    /// "in a Korean conversation" and "on English keys" mean this context.
    func context(korean: Bool, _ item: Item) {
        let word = korean ? "안녕" : "the"
        d.clearField()
        d.type(word)
        guard let f = field() else {
            item.markUnreadable("context=unreadable")
            return
        }
        if hasHangul(f) != korean {
            d.tapSlot(.left)
            item.note("context=\(q(f)) flip")
            item.noteField("context-after-flip", field())
        } else {
            item.note("context=\(q(f))")
        }
        d.type(" ")
        d.clearField()
    }

    // MARK: Task 6.8 (feature plan) items 1-11

    func checks68() {
        let ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11].map { "6.8-\($0)" }  // 6.8-10 is test4_memory's
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
        it.noteField("typed", field())
        d.tapSlot(.right)
        it.expect("after-tap", field(), "안녕하세요 ")
        finish(it)

        it = Item("6.8-5")
        d.clearField()
        d.type("omw")
        noteSlot(it, "right", readSlot(.right, it))
        d.type(" ")
        it.noteField("after-space", field())
        finish(it, record: true)

        write("6.8-6", "SKIP", "no contacts in the simulator")

        it = Item("6.8-7")
        context(korean: true, it)  // "in a Korean conversation"; 6.8-5 left an English word before this
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
        translate68(it)  // the Translate part (Sprint 002, NetworkChecks.swift)
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
            let f = field()
            let problems = d.takeProblems()
            if problems.isEmpty {
                write("6.8-9", "PENDING", "field=\(q(f))")
            } else {
                write("6.8-9", "FAIL", "unreadable: field=\(q(f)) problems=\(q(problems.joined(separator: "; ")))")
            }
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
        // Vision misreads the unquoted jamo `ㅗ디ㅣㅐ` (keyboard-ui 001): the slot's label stands in, with its ink.
        let left = labelFallback(.left, it, readSlot(.left, it)) { hasHangul($0) }
        expectSlot(it, "left", left, "Hangul") { hasHangul($0) }
        d.tapSlot(.left)
        if let f = field() {
            it.require("after-tap", hasHangul(f) && !hasLatinLetter(f) && f.hasSuffix(" "),
                       "\(q(f)) want the Korean reading plus a space")
        } else {
            it.markUnreadable("after-tap=unreadable")
        }
        finish(it)

        it = Item("ws-2")
        d.clearField()
        d.type("hello.")
        d.type(" ")
        it.expect("field", field(), "hello. ")
        expectEmpty(it, "left", readSlot(.left, it))
        finish(it)

        it = Item("ws-3")
        d.clearField()
        d.type("hello\n")
        it.expect("field", field(), "hello\n")
        expectEmpty(it, "left", readSlot(.left, it))
        finish(it)
        d.clearField()
    }

    // MARK: Task 8.5 (feature plan), the offline part

    func checks85() {
        if notReady(["8.5-1o", "8.5-2o", "8.5-6o", "8.5-7o", "8.5-8o", "8.5-9o"]) { return }

        // The drafts end with a space, as sending would: it ends the last word, so its reading has settled. Since
        // keyboard-ui 001 the bar's action stays visible while a word is typed; 8.5-8o records it with the cursor
        // right after the last letter.
        var it = Item("8.5-1o")
        d.clearField()
        typeCode("ru", it)
        d.type(": 누나 노트 고마워 누나 덕분에 살았다 ")
        it.expect("field", field(), "ru: 누나 노트 고마워 누나 덕분에 살았다 ")
        let russian = readSlot(.center, it, languages: Reader.labelLanguages("Русский"))
        expectSlot(it, "center", russian, q("Русский")) { $0.contains("Русский") }
        finish(it)

        it = Item("8.5-2o")
        d.clearField()
        d.type("ru")
        it.noteField("ru-again", field())
        d.clearField()
        typeCode("zh", it)
        d.type(": 안녕 ")
        it.noteField("taught", field())
        d.clearField()
        d.type("zh ")
        it.noteField("zh-space", field())
        finish(it, record: true)

        it = Item("8.5-6o")
        d.clearField()
        typeCode("ok", it)
        d.type(": 내일 봐 ")
        it.expect("field", field(), "ok: 내일 봐 ")
        expectSlot(it, "center", readSlot(.center, it), q("English")) { $0.contains("English") }
        finish(it)

        it = Item("8.5-7o")
        d.clearField()
        typeCode("ko", it)
        d.type(": 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠 ")
        it.expect("field", field(), "ko: 낼 시간되? 같이 밥먹자 ㅋㅋ 안되면 말해죠 ")
        expectSlot(it, "center", readSlot(.center, it), q("Polish")) { $0.contains("Polish") }
        finish(it)

        it = Item("8.5-8o")
        d.clearField()
        typeCode("ko", it)
        d.type(": 오늘 진짜 길었어\n\n낼 아침에 전화할게\n\n늦으면 미안 ㅠㅠ")
        it.noteField("field", field())
        noteSlot(it, "center", readSlot(.center, it))
        finish(it, record: true)

        it = Item("8.5-9o")
        context(korean: false, it)  // "on English keys"; 8.5-8o left a Korean word before this
        let spanish = "me encanta el color de tu chaqueta, donde la conprastes? jaja "
        d.type(spanish)
        it.expect("field", field(), spanish)
        expectSlot(it, "center", readSlot(.center, it), q("Polish")) { $0.contains("Polish") }
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
        // Each round must really hide the keyboard and bring Protly back, or the numbers are not 30 presentations.
        var hidden = 0
        var shown = 0
        for i in 1...30 {
            d.dismissKeyboard()
            d.pause(1)
            let after = d.current()
            if after == .none { hidden += 1 } else { d.log("round \(i): \(after.rawValue) after Dismiss") }
            if d.field.waitForExistence(timeout: 2) { d.field.tap() }
            // 8 s: run 41 had one round of 30 where Protly took just over 4 s to come back.
            if d.wait(for: .protly, timeout: 8) { shown += 1 } else { d.log("round \(i): no Protly after the tap") }
            d.pause(1)
        }
        d.mark("mem-end")
        d.pause(3)  // and one after the end mark
        let problems = d.takeProblems()
        let extra = problems.isEmpty ? "" : " problems=\(q(problems.joined(separator: "; ")))"
        if hidden == 30 && shown == 30 && problems.isEmpty {
            write("6.8-10", "PENDING", "presentations=30/30")
        } else {
            write("6.8-10", "FAIL", "unreadable: hidden \(hidden)/30, Protly shown \(shown)/30\(extra)")
        }
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
        let home = d.savePNG("c-icon-home")
        // The tower judges the crop; a missing icon or crop is the CI's failure to show it (ProtlyCIApp is installed
        // by run-shots.sh), so FAIL unreadable.
        if icon.exists && icon.isHittable {
            let frame = icon.frame
            let f = String(format: "{%.1f,%.1f,%.1f,%.1f}", frame.minX, frame.minY, frame.width, frame.height)
            do {
                try icon.screenshot().pngRepresentation.write(to: d.out.appendingPathComponent("c-icon.png"))
                if home {
                    d.append("CHECK icon RECORD \(f) found on page \(page + 1) (c-icon.png, c-icon-home.png)", to: "checks.txt")
                } else {
                    d.append("CHECK icon FAIL unreadable: \(f) found, c-icon-home.png not written", to: "checks.txt")
                }
            } catch {
                d.log("icon: could not write the crop: \(error)")
                d.append("CHECK icon FAIL unreadable: \(f) found, c-icon.png not written", to: "checks.txt")
            }
        } else {
            d.savePNG("c-icon")
            d.append("CHECK icon FAIL unreadable: no Protly icon after \(page) swipes (c-icon.png)", to: "checks.txt")
        }
        d.log("icon: page \(page + 1), exists \(icon.exists)")
    }

    // MARK: Probe (plan Task 2.2)

    /// Sprint 002's probe: the panel's text and button positions around one Translate, and how the Allow Paste prompt
    /// shows for a Read clipboard. Full Access is test0_access's (run-shots.sh dumps the preferences around it).
    func probe() {
        let p = { (line: String) in self.d.append(line, to: "probe.txt") }
        p("== sprint 002 probe (keyboard-ui 003: the strip and the streamed card)")
        p("full access: \(fullAccessHow)")
        p("network key: \(Self.network)")
        guard ready else {
            p("protly not reached: \(d.takeProblems())")
            return
        }
        let it = Item("probe")
        registerPasteMonitor()  // the probe tries both Allow Paste paths
        d.clearField()
        if Self.network && send(it) {
            d.type("내일 봐 ")
            if let row1 = d.rowOne() {
                p(String(format: "row 1 top %.2f pt, panel %@, button band %@", row1,
                         NSCoder.string(for: d.panelRect(row1: row1)), NSCoder.string(for: d.panelButtonBand(row1: row1))))
                d.savePNG("probe-bar")
                let t0 = Date()
                d.tapSlot(.center, settle: 0)
                // keyboard-ui 003: the strip in the bar while the call runs, then the card streaming in. The trees
                // show what KeyboardTree.swift reads (parts, labels, frames, enabled).
                d.pause(0.5)
                d.savePNG("probe-strip")
                try? d.app.debugDescription.write(to: d.out.appendingPathComponent("tree-probe-strip.txt"),
                                                  atomically: true, encoding: .utf8)
                p("strip: \(q(d.callView()?.stripText))")
                var streamed = false
                for _ in 0..<40 where !streamed {
                    if let v = d.callView(), !v.cardRows.body.isEmpty {
                        streamed = true
                        p(String(format: "first text after %.1f s: %@ buttons %@", Date().timeIntervalSince(t0),
                                 q(v.cardRows.body.first), q(v.buttons(v.card))))
                        d.savePNG("probe-card-streaming")
                        try? d.app.debugDescription.write(to: d.out.appendingPathComponent("tree-probe-streaming.txt"),
                                                          atomically: true, encoding: .utf8)
                    } else {
                        d.pause(0.25)
                    }
                }
                let r = waitCall(it, primary: "Replace", busy: "Translating", name: "probe-result")
                p(String(format: "result after %.1f s: %@ card %@ strip %@", Date().timeIntervalSince(t0),
                         "\(r.end)", q(r.text), q(r.strip)))
                try? d.app.debugDescription.write(to: d.out.appendingPathComponent("tree-probe-card.txt"),
                                                  atomically: true, encoding: .utf8)
                probePanel("probe-panel-result", row1, p)
                d.pause(0.6)
                tapPanelButton("Cancel", row1, it)
                p("after Cancel: field \(q(field())), card \(d.callView()?.card.count ?? -1) elements")
            }
        } else {
            p("panel probe skipped: no network key")
        }
        resetKeyboard()

        // Allow Paste: a note-shaped clipboard sends no request.
        let paste = readClipboard(it, "protly about me v1\nprobe", waitFor: ["Save"], sends: false, probe: p)
        p("clipboard panel: \(q(paste?.text))")
        if let row1 = paste?.row1 {  // measured before the tap: the panel now covers the keys
            probePanel("probe-panel-confirm", row1, p)
            tapPanelButton("Cancel", row1, it)
        }
        resetKeyboard()
        p("problems: \(d.takeProblems()) notes: \(it.evidence)")
    }

    private func probePanel(_ name: String, _ row1: CGFloat, _ p: (String) -> Void) {
        let screen = XCUIScreen.main.screenshot()
        d.savePNG(name, screen)
        guard let seen = reader.read(in: d.panelRect(row1: row1), of: screen, points: d.width, label: name) else {
            p("\(name): vision error")
            return
        }
        p("\(name): \(q(seen.text))")
        for w in seen.words {
            p(String(format: "  word %@ at x %.1f y %.1f w %.1f h %.1f", q(w.text), w.rect.minX, w.rect.minY,
                     w.rect.width, w.rect.height))
        }
    }
}
