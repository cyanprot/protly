import ProtlyCore
import UIKit
import XCTest

/// ProtlyGeometry (ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift), copied: this target cannot import it.
enum Geo {
    static let rowPitch: CGFloat = 54
    static let keyHeight: CGFloat = 43
    static let sideInset: CGFloat = 11.0 / 3
    /// Apple's band above row 1, the fallback when row 1 cannot be found in a screenshot.
    static let band: CGFloat = 52
    /// The bar's text row (ProtlyGeometry.toolbarHeight) ends half a row gap above row 1's keys.
    static let barHeight: CGFloat = 29
    static let barBottom: CGFloat = (rowPitch - keyHeight) / 2
}

enum Board: String {
    case protly, emoji, english, none
}

/// The bar's three equal slots (ProtlyBar.swift): flip, action, suggestion.
enum Slot: Int, CaseIterable {
    case left, center, right

    var name: String { ["left", "center", "right"][rawValue] }
}

/// One tap on Protly. Symbols are on the 123 layer, which `layer123` opens and `layerABC` closes.
enum Tap: Equatable {
    case letter(Character)
    case symbol(Character)
    case shift, space, ret, layer123, layerABC
}

/// Text to Protly taps (no actor: plain functions of the text).
enum Typing {
    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// The 123 layer (KeyboardKit's numeric input set): rows 1 and 2 have 10 keys like the letters' row 1; row 3
    /// has 5 wide keys (14% of the width each) between the #+= key and delete.
    static let symbolRows = ["1234567890", "-/:;()$&@\u{201D}", ".,?!\u{2019}"]

    static func isHangul(_ ch: Character) -> Bool {
        guard ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value else { return false }
        return (0xAC00...0xD7A3).contains(v) || (0x3131...0x318E).contains(v)
    }

    /// The taps that type `text`, or nil when a character has no key.
    static func taps(for text: String) -> [Tap]? {
        var result: [Tap] = []
        var numeric = false
        var hangul = ""
        func letters() {
            if numeric {
                result.append(.layerABC)
                numeric = false
            }
        }
        func flushHangul() -> Bool {
            guard !hangul.isEmpty else { return true }
            guard let keys = KeyEncoder.keys(forHangul: hangul) else { return false }
            letters()
            for k in keys {
                if k.shift == .manual { result.append(.shift) }
                result.append(.letter(k.letter))
            }
            hangul = ""
            return true
        }
        for ch in text {
            if isHangul(ch) {
                hangul.append(ch)
                continue
            }
            guard flushHangul() else { return nil }
            if ch == " " {
                result.append(.space)
                numeric = false  // KeyboardKit: space goes back to the letters
            } else if ch == "\n" {
                result.append(.ret)
            } else if ch.isASCII, ch.isLetter {
                letters()
                if ch.isUppercase { result.append(.shift) }
                result.append(.letter(Character(ch.lowercased())))
            } else if symbolRows.contains(where: { $0.contains(ch) }) {
                if !numeric {
                    result.append(.layer123)
                    numeric = true
                }
                result.append(.symbol(ch))
            } else {
                return nil
            }
        }
        guard flushHangul() else { return nil }
        if numeric { result.append(.layerABC) }
        return result
    }
}

/// Drives the CI host and the Protly keyboard: launch, keyboard switching, typing by coordinate, the bar's slots,
/// screenshots and logs. Shared by KeyboardShotsUITests (layout) and PhoneChecksUITests (phone checks).
///
/// Protly's keys are drawn in another process, so XCUITest cannot see them: never `typeText` (hardware-style events
/// skip the extension) and never `app.keyboards` for Protly. Keys, bar slots and the dock globe are tapped by
/// coordinate. Every file goes to $SHOTS_DIR (xcodebuild passes TEST_RUNNER_SHOTS_DIR).
@MainActor
final class Driver {
    let test: XCTestCase
    let app = XCUIApplication()
    let out: URL
    private(set) var width: CGFloat = 390
    /// true: a helper that cannot do its job fails the test (layout scenarios). false: it only logs and collects the
    /// message in `problems`; the phone checks put it in their CHECK lines and keep going.
    var strict = true
    private(set) var problems: [String] = []
    /// Seconds after each key tap.
    var keyPause: TimeInterval = 0.4
    /// Trees are dumped once per test run, not once per Driver.
    private static var dumped: Set<String> = []

    init(test: XCTestCase) throws {
        self.test = test
        let env = ProcessInfo.processInfo.environment
        let path = env["SHOTS_DIR"] ?? (env["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()) + "/protly-shots"
        out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func launch(arguments: [String] = []) {
        app.launchArguments = arguments
        app.launch()
        let frame = app.windows.firstMatch.frame
        if frame.width > 0 { width = frame.width }
    }

    func fail(_ message: String) {
        log("problem: \(message)")
        problems.append(message)
        if strict { XCTFail(message) }
    }

    func takeProblems() -> [String] {
        defer { problems = [] }
        return problems
    }

    // MARK: Keyboards

    func current() -> Board {
        let keys = app.keyboards.keys
        if keys["q"].exists || keys["Q"].exists { return .english }
        let emoji = NSPredicate(format: "label CONTAINS[c] 'Frequently Used' OR label CONTAINS[c] 'Smileys' "
            + "OR label CONTAINS[c] 'Search Emoji' OR placeholderValue CONTAINS[c] 'Search Emoji'")
        if app.descendants(matching: .any).matching(emoji).firstMatch.exists { return .emoji }
        return screenshot()?.keyboardTop() != nil ? .protly : .none
    }

    func wait(for board: Board, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let now = current()
            dumpOnce(now.rawValue)
            if now == board { return true }
            pause(0.5)
        } while Date() < end
        return false
    }

    func waitForKeyboard(timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if current() != .none { return true }
            pause(0.5)
        } while Date() < end
        log("no keyboard after \(Int(timeout)) s")
        return false
    }

    var field: XCUIElement { app.descendants(matching: .any)["field"] }

    func focusField() {
        if field.waitForExistence(timeout: 3) {
            field.tap()
            log("tapped the field")
        } else {
            log("field not found")
        }
        _ = waitForKeyboard()
    }

    /// Protly up in the host, from the globe's list or by globe taps. Settings is the layout scenarios' fallback.
    @discardableResult
    func ensureProtly() -> Bool {
        if !waitForKeyboard() { focusField() }
        if wait(for: .protly, timeout: 2) || pick(.protly) || cycle(to: .protly, taps: 3) { return true }
        fail("protly keyboard not reached")
        return false
    }

    /// Taps the dock globe until `board` is up (a fallback: the order after an app switch is not the list order).
    @discardableResult
    func cycle(to board: Board, taps: Int) -> Bool {
        for i in 0...taps {
            if wait(for: board, timeout: i == 0 ? 1.5 : 4) {
                log("\(board.rawValue) after \(i) globe taps")
                return true
            }
            if i < taps { tapGlobe() }
        }
        log("\(board.rawValue) not reached after \(taps) globe taps; now \(current().rawValue)")
        return false
    }

    /// Long-presses the dock globe and picks `board` in the list ("Protly, Korean", "Emoji", "English (US)").
    @discardableResult
    func pick(_ board: Board) -> Bool {
        let name: String
        switch board {
        case .protly: name = "Protly"
        case .emoji: name = "Emoji"
        case .english: name = "English"
        case .none: return false
        }
        globePoint().press(forDuration: 1.2)
        pause(0.8)
        dumpOnce("globe-menu")
        let cell = app.cells.matching(NSPredicate(format: "label BEGINSWITH[c] %@", name)).firstMatch
        guard cell.waitForExistence(timeout: 2) else {
            log("no \(name) in the globe list")
            let dismiss = app.descendants(matching: .any)["PopoverDismissRegion"]
            if dismiss.exists { dismiss.tap() }
            return false
        }
        let label = cell.label  // read before the tap closes the list
        cell.tap()
        let ok = wait(for: board, timeout: 4)
        log("picked \(label) from the globe list: \(ok ? board.rawValue : current().rawValue)")
        return ok
    }

    /// Protly -> Emoji with a tap on the dock globe (Emoji follows Protly in the list), then back to Protly from
    /// the globe's list. iOS 26's Emoji keyboard has no ABC key.
    func emojiRoundTrip() {
        tapGlobe()
        if wait(for: .emoji, timeout: 4) {
            log("emoji after a globe tap")
        } else {
            log("a globe tap gave \(current().rawValue), not emoji")
            if !pick(.emoji) && !cycle(to: .emoji, taps: 3) { fail("emoji keyboard not reached") }
        }
        if !pick(.protly) && !cycle(to: .protly, taps: 3) { fail("protly keyboard not reached from Emoji") }
    }

    /// English from the globe's long-press list, else by globe taps.
    func switchToEnglish() {
        if !pick(.english) && !cycle(to: .english, taps: 3) { fail("english keyboard not reached") }
    }

    /// The dock's globe: the lowest "Next keyboard" button (Emoji has a second one in its own bottom row).
    /// Measured in run 1 at {{8.5, 775.7}, {68.1, 68.7}} on the iPhone 13 Pro; that is the fallback.
    func globePoint() -> XCUICoordinate {
        let buttons = app.buttons
            .matching(NSPredicate(format: "label ==[c] 'Next keyboard'"))
            .allElementsBoundByIndex
            .map { $0.frame }
            .filter { $0.width > 0 }
        if let dock = buttons.max(by: { $0.minY < $1.minY }), dock.minY > height() * 0.85 {
            return point(dock.midX, dock.midY)
        }
        log("dock globe not found: using its run 1 position")
        return point(42.5, height() - 34)
    }

    func tapGlobe() {
        globePoint().tap()
        log("globe tapped")
    }

    /// Adds Protly in Settings > General > Keyboard > Keyboards > Add New Keyboard (the fallback of Task 2.2).
    func addKeyboardInSettings() {
        let s = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        s.launch()
        let steps: [(String, NSPredicate)] = [
            ("General", NSPredicate(format: "label ==[c] 'General'")),
            ("Keyboard", NSPredicate(format: "label ==[c] 'Keyboard'")),
            ("Keyboards", NSPredicate(format: "label ==[c] 'Keyboards'")),
            ("Add New Keyboard", NSPredicate(format: "label BEGINSWITH[c] 'Add New Keyboard'")),
            ("Protly", NSPredicate(format: "label CONTAINS[c] 'Protly'")),
        ]
        for (name, predicate) in steps {
            guard tapRow(in: s, predicate) else {
                log("Settings: \(name) not found")
                dumpOnce("settings-\(name)", s)
                s.terminate()
                return
            }
            log("Settings: \(name)")
            pause(1)
        }
        dumpOnce("settings-done", s)
        s.terminate()
    }

    private func tapRow(in a: XCUIApplication, _ predicate: NSPredicate) -> Bool {
        for _ in 0..<6 {
            let e = a.descendants(matching: .any).matching(predicate).firstMatch
            if e.waitForExistence(timeout: 2) && e.isHittable {
                e.tap()
                return true
            }
            a.swipeUp()
        }
        return false
    }

    // MARK: Host field (ios-app/CI/Host)

    /// The field's text as XCUITest reads it (exact, marked text included); nil when the field cannot be found.
    func fieldText() -> String? {
        guard field.waitForExistence(timeout: 2) else {
            log("field not found")
            return nil
        }
        return field.value as? String ?? ""
    }

    /// The host's Clear button empties the field (no keys are involved).
    func clearField() {
        for attempt in 1...2 {
            let button = app.buttons["clear"]
            guard button.waitForExistence(timeout: 2) else {
                fail("clear button not found")
                return
            }
            button.tap()
            pause(0.6)
            let now = fieldText()
            if now == "" { return }
            log("field not empty after Clear (attempt \(attempt)): \(String(reflecting: now ?? "<no field>"))")
        }
        fail("Clear left text in the field")
    }

    /// The host's Dismiss button takes the focus from the field, which hides the keyboard.
    func dismissKeyboard() {
        let button = app.buttons["dismiss"]
        guard button.waitForExistence(timeout: 2) else {
            fail("dismiss button not found")
            return
        }
        button.tap()
    }

    // MARK: Protly keys

    /// Row 1's top in points, from a screenshot (measure.py's way); nil without a keyboard.
    func rowOne(_ shot: Shot? = nil) -> CGFloat? {
        guard let s = shot ?? screenshot(), let top = s.keyboardTop() else { return nil }
        return s.row1Top(below: top, column: keyX(row: 0, index: 1)) ?? (CGFloat(top) / s.scale + Geo.band)
    }

    /// Types `text` on Protly. Hangul goes in as its Dubeolsik keys (ProtlyCore KeyEncoder), capitals and the
    /// shifted jamo with a shift tap, symbols on the 123 layer, "\n" with return.
    @discardableResult
    func type(_ text: String) -> Bool {
        guard let taps = Typing.taps(for: text) else {
            fail("no keys for \(String(reflecting: text))")
            return false
        }
        guard let shot = screenshot(), let top = shot.keyboardTop(), let row1 = rowOne(shot) else {
            fail("no keyboard to type on")
            return false
        }
        log(String(format: "typing: keyboard top %.2f, row 1 %.2f", CGFloat(top) / shot.scale, row1))
        for t in taps {
            let (x, y) = position(of: t, row1: row1)
            point(x, y).tap()
            pause(keyPause)
        }
        log("typed \(String(reflecting: text))")
        return true
    }

    /// Where a tap lands, in points. Bottom-row widths are KeyboardKit's iPhone portrait percentages of the width
    /// inside ProtlyRoot's side padding: 123/ABC 12.3%, the protly key 12.3%, return 25%, space the rest.
    func position(of tap: Tap, row1: CGFloat) -> (CGFloat, CGFloat) {
        let inner = width - 2 * Geo.sideInset
        func y(_ row: Int) -> CGFloat { row1 + CGFloat(row) * Geo.rowPitch + Geo.keyHeight / 2 }
        switch tap {
        case .letter(let c):
            for (r, row) in Typing.letterRows.enumerated() {
                if let i = row.firstIndex(of: c) { return (keyX(row: r, index: row.distance(from: row.startIndex, to: i)), y(r)) }
            }
            return (width / 2, y(1))  // unreachable: taps(for:) only makes a-z letters
        case .symbol(let c):
            for (r, row) in Typing.symbolRows.enumerated() {
                guard let i = row.firstIndex(of: c) else { continue }
                let index = row.distance(from: row.startIndex, to: i)
                if r < 2 { return (keyX(row: 0, index: index), y(r)) }
                return (Geo.sideInset + inner * (0.15 + 0.14 * CGFloat(index) + 0.07), y(2))
            }
            return (width / 2, y(1))  // unreachable: taps(for:) only makes listed symbols
        case .shift:
            return (Geo.sideInset + inner * 0.065, y(2))
        case .space:
            return (width * 0.45, y(3))  // space spans about 100...290 pt
        case .ret:
            return (width - Geo.sideInset - inner * 0.125, y(3))
        case .layer123, .layerABC:
            return (Geo.sideInset + inner * 0.0615, y(3))
        }
    }

    /// Key centers: the rows are centered (10, 9 and 7 letters), one key pitch across = width / 10 inside the insets.
    func keyX(row: Int, index: Int) -> CGFloat {
        let pitch = (width - 2 * Geo.sideInset) / 10
        let first: [CGFloat] = [4.5, 4, 3]
        return width / 2 + (CGFloat(index) - first[row]) * pitch
    }

    // MARK: The bar

    /// A slot's area in points: its third of the bar's text row, kept off the glass's round corners.
    func slotRect(_ slot: Slot, row1: CGFloat) -> CGRect {
        let third = (width - 2 * Geo.sideInset) / 3
        var x0 = Geo.sideInset + third * CGFloat(slot.rawValue)
        var x1 = x0 + third
        if slot == .left { x0 = max(x0, 16) }
        if slot == .right { x1 = min(x1, width - 16) }
        let top = row1 - Geo.barBottom - Geo.barHeight - 2
        return CGRect(x: x0, y: top, width: x1 - x0, height: Geo.barHeight + 3)
    }

    /// Taps a bar slot at its center. false without a keyboard.
    @discardableResult
    func tapSlot(_ slot: Slot) -> Bool {
        guard let row1 = rowOne() else {
            fail("no keyboard for a \(slot.name) slot tap")
            return false
        }
        let r = slotRect(slot, row1: row1)
        point(r.midX, row1 - Geo.barBottom - Geo.barHeight / 2).tap()
        pause(0.8)
        log("tapped the \(slot.name) slot")
        return true
    }

    // MARK: Output

    func shoot(_ name: String, expect board: Board) {
        pause(1.5)  // let the keyboard's animation settle
        let now = current()
        if now != board { fail("\(name): expected \(board.rawValue), found \(now.rawValue)") }
        dumpOnce(name)  // the inputView frame tells the keyboard's height from iOS's side
        let s = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: s)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        if save(s.pngRepresentation, as: name + ".png") { log("\(name): \(now.rawValue)") }
    }

    /// Writes a screenshot (the current screen when nil) as <name>.png.
    func savePNG(_ name: String, _ shot: XCUIScreenshot? = nil) {
        _ = save((shot ?? XCUIScreen.main.screenshot()).pngRepresentation, as: name + ".png")
    }

    private func save(_ data: Data, as file: String) -> Bool {
        do {
            try data.write(to: out.appendingPathComponent(file))
            return true
        } catch {
            log("\(file): could not write: \(error)")
            return false
        }
    }

    func screenshot(_ s: XCUIScreenshot? = nil) -> Shot? {
        Shot(s ?? XCUIScreen.main.screenshot(), points: width)
    }

    func height() -> CGFloat {
        let h = app.windows.firstMatch.frame.height
        return h > 0 ? h : 844
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: x, dy: y))
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func log(_ line: String) {
        append(line, to: "ui-log.txt")
    }

    /// `MARK <name> <epoch>`: checks.py matches it to the memory sampler's lines (mem.txt) by time.
    func mark(_ name: String) {
        log("MARK \(name) \(String(format: "%.3f", Date().timeIntervalSince1970))")
    }

    /// Appends one line to a file in the output folder (created on first use). Every test class shares the files.
    func append(_ line: String, to file: String) {
        let url = out.appendingPathComponent(file)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                print("could not append to \(file): \(error)")
            }
        } else {
            do { try data.write(to: url) } catch { print("could not write \(file): \(error)") }
        }
    }

    func dumpOnce(_ name: String, _ a: XCUIApplication? = nil) {
        guard Self.dumped.insert(name).inserted else { return }
        let tree = (a ?? app).debugDescription
        try? tree.write(to: out.appendingPathComponent("tree-\(name).txt"), atomically: true, encoding: .utf8)
    }
}

/// A screenshot's pixels, for finding the keyboard the way measure.py does.
struct Shot {
    let width: Int
    let height: Int
    /// Pixels per point.
    let scale: CGFloat
    let image: XCUIScreenshot
    private let bytes: [UInt8]

    @MainActor
    init?(_ screenshot: XCUIScreenshot, points: CGFloat) {
        guard let cg = screenshot.image.cgImage, points > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        guard drawn else { return nil }
        width = cg.width
        height = cg.height
        scale = CGFloat(cg.width) / points
        image = screenshot
        bytes = buffer
    }

    private func diff(_ x: Int, _ y: Int, _ ref: (Int, Int, Int)) -> Int {
        let p = rgb(x, y)
        return abs(p.0 - ref.0) + abs(p.1 - ref.1) + abs(p.2 - ref.2)
    }

    private func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// measure.py: down the center column from 35% of the height, 6 rows that differ from the host background.
    func keyboardTop() -> Int? {
        let x = width / 2
        let bg = rgb(x, Int(Double(height) * 0.30))
        var y = Int(Double(height) * 0.35)
        while y < height - 6 {
            if (0..<6).allSatisfy({ diff(x, y + $0, bg) > 24 }) { return y }
            y += 1
        }
        return nil
    }

    /// measure.py: the first run of at least 30 pt that differs from the keyboard background, in points.
    func row1Top(below top: Int, column: CGFloat) -> CGFloat? {
        let x = min(width - 1, max(0, Int((column * scale).rounded())))
        let start = top + Int((6 * scale).rounded())
        guard start < height else { return nil }
        let kb = rgb(x, start)
        let run = Int((30 * scale).rounded())
        var y = start
        while y < height {
            if diff(x, y, kb) > 24 {
                let y0 = y
                while y < height && diff(x, y, kb) > 24 { y += 1 }
                if y - y0 >= run { return CGFloat(y0) / scale }
            }
            y += 1
        }
        return nil
    }

    /// Pixels in `rect` (points) far (> 96, measure.py's TEXT_DIFF) from the color at `background` (points):
    /// text in a bar slot. An empty slot counts (near) zero.
    func ink(in rect: CGRect, background: CGPoint) -> Int {
        let bx = min(width - 1, max(0, Int(background.x * scale)))
        let by = min(height - 1, max(0, Int(background.y * scale)))
        let bg = rgb(bx, by)
        let x0 = max(0, Int(rect.minX * scale)), x1 = min(width, Int(rect.maxX * scale))
        let y0 = max(0, Int(rect.minY * scale)), y1 = min(height, Int(rect.maxY * scale))
        guard x0 < x1, y0 < y1 else { return 0 }
        var n = 0
        for y in y0..<y1 {
            for x in x0..<x1 where diff(x, y, bg) > 96 { n += 1 }
        }
        return n
    }
}
