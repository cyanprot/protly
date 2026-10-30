import UIKit
import XCTest

/// The keyboard screenshots of docs/plans/2026-10-29-keyboard-visual.md (Task 2), measured by ios-app/CI/measure.py.
///
/// One PNG per scenario goes to $SHOTS_DIR (xcodebuild passes TEST_RUNNER_SHOTS_DIR) and to the result bundle.
/// `ui-log.txt` records each step and `tree-*.txt` the accessibility tree the first time each keyboard is seen.
/// Driver.swift holds the helpers (typing by coordinate, keyboard switching, screenshots, logs).
final class KeyboardShotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScenarios() throws {
        let d = try Driver(test: self)
        d.log("== KeyboardShotsUITests.testScenarios")
        d.launch()
        let frame = d.app.windows.firstMatch.frame
        d.log("screen \(frame.size.width)x\(frame.size.height) pt, shots in \(d.out.path)")

        // Protly is first in AppleKeyboards (run-shots.sh); otherwise the globe's list or Settings brings it.
        if !d.waitForKeyboard() { d.focusField() }
        d.waitOutStandIn()
        if !d.wait(for: .protly, timeout: 2) && !d.pick(.protly) {
            d.log("Protly not in the globe list: adding it in Settings")
            d.addKeyboardInSettings()
            d.app.activate()
            if !d.waitForKeyboard() { d.focusField() }
            if !d.pick(.protly) && !d.cycle(to: .protly, taps: 3) { XCTFail("protly keyboard not reached") }
        }
        d.shoot("02-first-open", expect: .protly)

        d.emojiRoundTrip()
        d.shoot("03-after-emoji", expect: .protly)

        XCUIDevice.shared.press(.home)
        d.pause(2)
        d.app.activate()
        if !d.waitForKeyboard() { d.focusField() }
        d.shoot("04-after-background", expect: .protly)

        d.emojiRoundTrip()
        d.shoot("05-after-second-emoji", expect: .protly)

        d.type("hello ")
        d.shoot("06-word-typed", expect: .protly)

        d.app.terminate()
        d.launch(arguments: ["-prefill", "see you tomorrow"])
        if !d.waitForKeyboard() { d.focusField() }
        d.shoot("07-empty-left-slot", expect: .protly)

        d.switchToEnglish()
        d.shoot("01-apple", expect: .english)
    }
}
