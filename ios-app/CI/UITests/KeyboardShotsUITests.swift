import UIKit
import XCTest

/// The keyboard screenshots of docs/plans/2026-10-29-keyboard-visual.md (Task 2), measured by ios-app/CI/measure.py.
///
/// One PNG per scenario goes to $SHOTS_DIR (xcodebuild passes TEST_RUNNER_SHOTS_DIR) and to the result bundle.
/// `ui-log.txt` records each step and `tree-*.txt` the accessibility tree the first time each keyboard is seen.
/// Protly's keys are drawn in another process, so XCUITest cannot see them: never `typeText` (hardware-style events
/// skip the extension) and never `app.keyboards` for Protly. Keys and the dock globe are tapped by coordinate.
final class KeyboardShotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScenarios() throws {
        try Driver(test: self).run()
    }
}

/// ProtlyGeometry (ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift), copied: this target cannot import it.
enum Geo {
    static let rowPitch: CGFloat = 54
    static let keyHeight: CGFloat = 43
    static let sideInset: CGFloat = 11.0 / 3
    /// Apple's band above row 1, the fallback when row 1 cannot be found in a screenshot.
    static let band: CGFloat = 52
}

enum Board: String {
    case protly, emoji, english, none
}

@MainActor
final class Driver {
    private let test: XCTestCase
    private let app = XCUIApplication()
    private let out: URL
    private var lines: [String] = []
    private var dumped: Set<String> = []
    private var width: CGFloat = 390

    init(test: XCTestCase) throws {
        self.test = test
        let env = ProcessInfo.processInfo.environment
        let path = env["SHOTS_DIR"] ?? (env["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()) + "/protly-shots"
        out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func run() {
        app.launch()
        let frame = app.windows.firstMatch.frame
        if frame.width > 0 { width = frame.width }
        log("screen \(frame.size.width)x\(frame.size.height) pt, shots in \(out.path)")

        // Protly should be first in AppleKeyboards (run-shots.sh); otherwise the globe or Settings brings it.
        if !waitForKeyboard() { focusField() }
        if !cycle(to: .protly, taps: 3, quiet: true) {
            log("Protly not reached with the globe: adding it in Settings")
            addKeyboardInSettings()
            app.activate()
            if !waitForKeyboard() { focusField() }
            _ = cycle(to: .protly, taps: 3)
        }
        shoot("02-first-open", expect: .protly)

        emojiRoundTrip()
        shoot("03-after-emoji", expect: .protly)

        XCUIDevice.shared.press(.home)
        pause(2)
        app.activate()
        if !waitForKeyboard() { focusField() }
        shoot("04-after-background", expect: .protly)

        emojiRoundTrip()
        shoot("05-after-second-emoji", expect: .protly)

        typeOnProtly(["h", "e", "l", "l", "o", " "])
        shoot("06-word-typed", expect: .protly)

        app.terminate()
        app.launchArguments = ["-prefill", "see you tomorrow"]
        app.launch()
        if !waitForKeyboard() { focusField() }
        shoot("07-empty-left-slot", expect: .protly)

        switchToEnglish()
        shoot("01-apple", expect: .english)
    }

    // MARK: Keyboards

    private func current() -> Board {
        let keys = app.keyboards.keys
        if keys["q"].exists || keys["Q"].exists { return .english }
        let emoji = NSPredicate(format: "label CONTAINS[c] 'Frequently Used' OR label CONTAINS[c] 'Smileys' "
            + "OR label CONTAINS[c] 'Search Emoji' OR placeholderValue CONTAINS[c] 'Search Emoji'")
        if app.descendants(matching: .any).matching(emoji).firstMatch.exists { return .emoji }
        return screenshot()?.keyboardTop() != nil ? .protly : .none
    }

    private func wait(for board: Board, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let now = current()
            dumpTree(now)
            if now == board { return true }
            pause(0.5)
        } while Date() < end
        return false
    }

    private func waitForKeyboard(timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if current() != .none { return true }
            pause(0.5)
        } while Date() < end
        log("no keyboard after \(Int(timeout)) s")
        return false
    }

    private func focusField() {
        let field = app.descendants(matching: .any)["field"]
        if field.waitForExistence(timeout: 3) {
            field.tap()
            log("tapped the field")
        } else {
            log("field not found")
        }
        _ = waitForKeyboard()
    }

    /// Taps the globe until `board` is up. The list order is Protly, Emoji, English, so 3 taps visit all.
    @discardableResult
    private func cycle(to board: Board, taps: Int, quiet: Bool = false) -> Bool {
        for i in 0...taps {
            if wait(for: board, timeout: i == 0 ? 1.5 : 4) {
                log("\(board.rawValue) after \(i) globe taps")
                return true
            }
            if i < taps { tapGlobe() }
        }
        log("\(board.rawValue) not reached after \(taps) globe taps; now \(current().rawValue)")
        if !quiet { XCTFail("\(board.rawValue) keyboard not reached") }
        return false
    }

    /// Protly -> Emoji with the dock globe (Emoji is next in the list), then Emoji's ABC key back to Protly.
    private func emojiRoundTrip() {
        guard cycle(to: .emoji, taps: 3) else { return }
        let abc = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'ABC'")).firstMatch
        if abc.exists && abc.isHittable {
            abc.tap()
            log("tapped Emoji's ABC")
            if wait(for: .protly, timeout: 4) { return }
            log("ABC did not return to Protly; now \(current().rawValue)")
        } else {
            log("no ABC key on Emoji")
        }
        cycle(to: .protly, taps: 3)
    }

    /// English from the globe's long-press list, else by globe taps.
    private func switchToEnglish() {
        let g = globe()
        if g.exists && g.isHittable {
            g.press(forDuration: 1.2)
        } else {
            globePoint().press(forDuration: 1.2)
        }
        pause(1)
        dumpOnce("globe-menu")
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] 'English'")).firstMatch
        if english.exists && english.isHittable {
            english.tap()
            log("picked \(english.label) from the globe list")
        } else {
            log("no English item in the globe list")
            tapGlobe()
        }
        cycle(to: .english, taps: 3)
    }

    private func globe() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] 'Next keyboard' OR identifier ==[c] 'Next keyboard'"))
            .firstMatch
    }

    /// The dock globe under the keyboard on a 390 x 844 pt Face ID iPhone, if XCUITest cannot see it.
    private func globePoint() -> XCUICoordinate {
        point(34, height() - 49)
    }

    private func tapGlobe() {
        let g = globe()
        if g.exists && g.isHittable {
            g.tap()
            log("globe tapped (element at \(g.frame))")
        } else {
            globePoint().tap()
            log("globe tapped (coordinate)")
        }
    }

    /// Adds Protly in Settings > General > Keyboard > Keyboards > Add New Keyboard (the fallback of Task 2.2).
    private func addKeyboardInSettings() {
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

    // MARK: Protly keys

    /// Taps QWERTY keys (and " " for space) at the positions of ProtlyGeometry, measured from row 1's top.
    private func typeOnProtly(_ keys: [String]) {
        guard let shot = screenshot(), let top = shot.keyboardTop() else {
            XCTFail("no keyboard to type on")
            return
        }
        let row1 = shot.row1Top(below: top, column: keyX(row: 0, index: 1)) ?? (CGFloat(top) / shot.scale + Geo.band)
        log(String(format: "typing: keyboard top %.2f, row 1 %.2f", CGFloat(top) / shot.scale, row1))
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for key in keys {
            let x: CGFloat
            let row: Int
            if key == " " {
                row = 3
                x = width * 0.45  // space spans about 100...290 pt
            } else if let r = rows.firstIndex(where: { $0.contains(key) }),
                      let i = rows[r].firstIndex(of: Character(key)) {
                row = r
                x = keyX(row: r, index: rows[r].distance(from: rows[r].startIndex, to: i))
            } else {
                XCTFail("no key for \(key)")
                continue
            }
            let y = row1 + CGFloat(row) * Geo.rowPitch + Geo.keyHeight / 2
            point(x, y).tap()
            pause(0.4)
        }
        log("typed \(keys.joined())")
    }

    /// Key centers: the rows are centered (10, 9 and 7 letters), one key pitch across = width / 10 inside the insets.
    private func keyX(row: Int, index: Int) -> CGFloat {
        let pitch = (width - 2 * Geo.sideInset) / 10
        let first: [CGFloat] = [4.5, 4, 3]
        return width / 2 + (CGFloat(index) - first[row]) * pitch
    }

    // MARK: Output

    private func shoot(_ name: String, expect board: Board) {
        pause(1.5)  // let the keyboard's animation settle
        let now = current()
        if now != board { XCTFail("\(name): expected \(board.rawValue), found \(now.rawValue)") }
        let s = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: s)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        do {
            try s.pngRepresentation.write(to: out.appendingPathComponent(name + ".png"))
            log("\(name): \(now.rawValue)")
        } catch {
            log("\(name): could not write the PNG: \(error)")
        }
    }

    private func screenshot() -> Shot? {
        Shot(XCUIScreen.main.screenshot(), points: width)
    }

    private func height() -> CGFloat {
        let h = app.windows.firstMatch.frame.height
        return h > 0 ? h : 844
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: x, dy: y))
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func log(_ line: String) {
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("ui-log.txt"), atomically: true, encoding: .utf8)
    }

    private func dumpTree(_ board: Board) {
        dumpOnce(board.rawValue)
    }

    private func dumpOnce(_ name: String, _ a: XCUIApplication? = nil) {
        guard dumped.insert(name).inserted else { return }
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
}
