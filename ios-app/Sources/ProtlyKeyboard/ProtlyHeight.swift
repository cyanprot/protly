import Combine
import KeyboardKit
import ObjectiveC
import UIKit

/// Pins the keyboard's height in portrait. Without a constraint iOS sizes the input view from the SwiftUI content
/// at each presentation, and the band above row 1 changed between first open, an Emoji round-trip and an app
/// switch (Sprint 5; docs/ios-keyboard-notes.md, "Simulator verification"). Landscape keeps iOS's own height:
/// its rows are KeyboardKit's, not ProtlyGeometry's.
@MainActor
final class ProtlyHeight {
    /// The bar's band and four rows, the last one trimmed: 257 pt.
    static let portrait = ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight
        + 4 * ProtlyGeometry.rowPitch - ProtlyGeometry.lastRowTrim

    private let constraint: NSLayoutConstraint
    private var orientation: AnyCancellable?
    private static var key: UInt8 = 0

    /// Call once from viewDidLoad. The pin lives as long as the controller.
    static func pin(_ controller: KeyboardInputViewController) {
        let pin = ProtlyHeight(view: controller.view, context: controller.state.keyboardContext)
        objc_setAssociatedObject(controller, &key, pin, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(view: UIView, context: KeyboardContext) {
        // 999, not required: iOS's own constraints win during its transitions instead of breaking ours.
        constraint = view.heightAnchor.constraint(equalToConstant: Self.portrait)
        constraint.priority = UILayoutPriority(999)
        orientation = context.$interfaceOrientation.sink { [constraint] in
            constraint.isActive = $0.isPortrait
        }
    }
}
