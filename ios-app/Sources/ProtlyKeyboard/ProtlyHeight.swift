import Combine
import Foundation
import KeyboardKit
import ObjectiveC
import os
import UIKit

/// Pins the keyboard's height in portrait so every presentation (first open, Emoji round-trip, app switch) shows
/// the same band above row 1 (Sprint 5; docs/ios-keyboard-notes.md, "Simulator verification"). Landscape keeps
/// iOS's own height: its rows are KeyboardKit's, not ProtlyGeometry's.
///
/// iOS draws its glass `hostTopMargin` above the height it gives a third-party keyboard. On a fresh presentation it
/// takes that margin out of the keyboard's own height, so the glass starts at the view's top. When the host app
/// comes back from the background with the keyboard up, it keeps the full height and draws the margin above the
/// view: an empty band 17 pt too tall (simulator runs 1-4). Then the pin drops by the margin, and ProtlyRoot keeps
/// the content at the bottom, so only the empty top of the bar's band goes under iOS's margin.
///
/// Logs the view's height at debug level (subsystem com.northprot.protly, category height): Console on a Mac
/// shows it for the phone, `log show --debug` for the simulator.
@MainActor
final class ProtlyHeight: NSObject {
    /// The bar's band and four rows, the last one trimmed: 257 pt.
    static let portrait = ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight
        + 4 * ProtlyGeometry.rowPitch - ProtlyGeometry.lastRowTrim
    /// Glass above the keyboard's height that iOS 26 adds for a third-party keyboard (measured in the simulator).
    static let hostTopMargin: CGFloat = 17

    private static let log = Logger(subsystem: "com.northprot.protly", category: "height")
    private static var key: UInt8 = 0

    private weak var view: UIView?
    private let constraint: NSLayoutConstraint
    private var orientation: AnyCancellable?
    private var bounds: NSKeyValueObservation?

    /// Call once from viewDidLoad. The pin lives as long as the controller.
    static func pin(_ controller: KeyboardInputViewController) {
        let pin = ProtlyHeight(controller)
        objc_setAssociatedObject(controller, &key, pin, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(_ controller: KeyboardInputViewController) {
        let view: UIView = controller.view
        self.view = view
        // 999, not required: iOS's own constraints win during its transitions instead of breaking ours.
        constraint = view.heightAnchor.constraint(equalToConstant: Self.portrait)
        constraint.priority = UILayoutPriority(999)
        super.init()

        orientation = controller.state.keyboardContext.$interfaceOrientation.sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.constraint.isActive = value.isPortrait
                self?.report("orientation \(value.rawValue)")
            }
        }
        bounds = view.layer.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue?.height != change.newValue?.height else { return }
            MainActor.assumeIsolated { self?.report("bounds") }
        }
        // Selector observers go away with this object.
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostBecameActive), name: .NSExtensionHostDidBecomeActive, object: nil
        )
        report("pinned")
    }

    @objc private func hostBecameActive(_ note: Notification) {
        constraint.constant = Self.portrait - Self.hostTopMargin
        report("host became active")
    }

    private func report(_ reason: String) {
        guard let view else { return }
        let height = Double(view.bounds.height)
        let window = Double(view.window?.bounds.height ?? -1)
        let pin = Double(constraint.constant)
        let active = constraint.isActive
        let vertical = view.constraintsAffectingLayout(for: .vertical).map { "\($0)" }.joined(separator: " | ")
        Self.log.debug("\(reason, privacy: .public): height \(height, privacy: .public) window \(window, privacy: .public) pin \(pin, privacy: .public) active \(active, privacy: .public) vertical \(vertical, privacy: .public)")
    }
}
