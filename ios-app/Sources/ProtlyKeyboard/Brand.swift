import SwiftUI

/// The northprot brand (`src/ui/tokens.css.js`), the keyboard's one accent (design D3): the center action pill and
/// the protly key. A paper pill with ink text when the keyboard is dark, an ink pill with paper text when it is light.
/// Keys, key sizes and the keyboard background stay Apple's (D2).
enum Brand {
    static let paperHex = 0xF5F0E6
    static let inkHex = 0x1A1F2E

    static let paper = color(paperHex)
    static let ink = color(inkHex)

    /// `scheme` is the keyboard's (KeyboardKit's `KeyboardContext.colorScheme`), never the host app's.
    static func pillFill(_ scheme: ColorScheme) -> Color { scheme == .dark ? paper : ink }
    static func pillText(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : paper }

    private static func color(_ hex: Int) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
