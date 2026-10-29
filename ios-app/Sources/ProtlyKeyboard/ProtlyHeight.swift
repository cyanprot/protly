import Combine
import Foundation
import KeyboardKit
import ObjectiveC
import os
import UIKit

/// Pins the keyboard's height in portrait so every presentation (first open, Emoji round-trip, app switch) gets
/// the same frame. Without it iOS picked a height per presentation and the band above row 1 changed (Sprint 5;
/// docs/ios-keyboard-notes.md, "Simulator verification"). Landscape keeps iOS's own height: its rows are
/// KeyboardKit's, not ProtlyGeometry's.
///
/// Logs the view's height at debug level (subsystem com.northprot.protly, category height): Console on a Mac
/// shows it for the phone, `log show --debug` for the simulator.
@MainActor
final class ProtlyHeight: NSObject {
    /// The bar's band and four rows, the last one trimmed: 257 pt.
    static let portrait = ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight
        + 4 * ProtlyGeometry.rowPitch - ProtlyGeometry.lastRowTrim

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

        // A UIInputView takes iOS's height unless it may size itself from its constraints.
        controller.inputView?.allowsSelfSizing = true
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
        // After an app switch iOS showed the keyboard 17 pt taller than the pin (simulator runs 1-3): ask again.
        // Selector observers go away with this object.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(hostChanged), name: .NSExtensionHostWillEnterForeground, object: nil)
        center.addObserver(self, selector: #selector(hostChanged), name: .NSExtensionHostDidBecomeActive, object: nil)
        report("pinned, allowsSelfSizing \(controller.inputView?.allowsSelfSizing ?? false)")
    }

    @objc private func hostChanged(_ note: Notification) {
        guard constraint.isActive, let view else { return }
        constraint.isActive = false
        constraint.isActive = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
        report(note.name.rawValue)
    }

    private func report(_ reason: String) {
        guard let view else { return }
        let height = Double(view.bounds.height)
        let window = Double(view.window?.bounds.height ?? -1)
        let safeTop = Double(view.safeAreaInsets.top)
        let pinned = constraint.isActive
        let vertical = view.constraintsAffectingLayout(for: .vertical).map { "\($0)" }.joined(separator: " | ")
        Self.log.debug("\(reason, privacy: .public): height \(height, privacy: .public) window \(window, privacy: .public) safe-top \(safeTop, privacy: .public) pin \(pinned, privacy: .public) vertical \(vertical, privacy: .public)")
    }
}
