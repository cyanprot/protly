//
//  Color+Keyboard.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-01-20.
//  Copyright © 2021-2025 Daniel Saidi. All rights reserved.
//

import SwiftUI

public extension Color {

    /// This color can be used instead of `clear` to make it
    /// register touches & gestures.
    static var clearInteractable: Self {
        Color.white.opacity(0.001)
    }

    /// The standard keyboard background color.
    static let keyboardBackground = KKColor.keyboardBackground

    /// The standard keyboard background color for dark appearance.
    static let keyboardBackgroundForDarkAppearance = KKColor.keyboardBackgroundForDarkAppearance

    /// The standard keyboard button background color.
    static let keyboardButtonBackground = KKColor.keyboardButtonBackground

    /// The standard keyboard button background color, adjusted for the iOS color scheme bug.
    static let keyboardButtonBackgroundForColorSchemeBug = KKColor.keyboardButtonBackgroundForColorSchemeBug

    /// The standard keyboard button background color for dark appearance.
    static let keyboardButtonBackgroundForDarkAppearance = KKColor.keyboardButtonBackgroundForDarkAppearance

    /// The standard keyboard button foreground color.
    static let keyboardButtonForeground = KKColor.keyboardButtonForeground

    /// The standard keyboard button foreground color for dark appearance.
    static let keyboardButtonForegroundForDarkAppearance = KKColor.keyboardButtonForegroundForDarkAppearance

    /// The standard keyboard button shadow color.
    static let keyboardButtonShadow = KKColor.keyboardButtonShadow

    /// The standard dark keyboard button background color.
    static let keyboardDarkButtonBackground = KKColor.keyboardDarkButtonBackground

    /// The standard dark keyboard button background color for the iOS color scheme bug.
    static let keyboardDarkButtonBackgroundForColorSchemeBug = KKColor.keyboardDarkButtonBackgroundForColorSchemeBug

    /// The standard dark keyboard button background color for dark apperance.
    static let keyboardDarkButtonBackgroundForDarkAppearance = KKColor.keyboardDarkButtonBackgroundForDarkAppearance

    /// The standard dark keyboard button foreground color.
    static var keyboardDarkButtonForeground: Self {
        KKColor.keyboardButtonForeground
    }
    
    /// The standard dark keyboard button foreground color for dark apperance.
    static var keyboardDarkButtonForegroundForDarkAppearance: Self {
        KKColor.keyboardButtonForegroundForDarkAppearance
    }
}

// MARK: - Contextual Colors

public extension Color {
    
    /// The standard keyboard button background color.
    static func keyboardBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        .keyboardBackground
    }

    /// The standard keyboard button background color.
    static func keyboardButtonBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardButtonBackgroundForColorSchemeBug :
            .keyboardButtonBackground
    }

    /// The standard keyboard button background color.
    ///
    /// This color is adjusted for display with Liquid Glass.
    static func keyboardButtonBackgroundLiquid(
        for colorScheme: ColorScheme
    ) -> Self {
        return colorScheme.isDark ?
            .keyboardButtonBackgroundForColorSchemeBug.opacity(0.55) :
            .keyboardButtonBackground
    }

    /// The standard keyboard button foreground color.
    static func keyboardButtonForeground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardButtonForegroundForDarkAppearance :
            .keyboardButtonForeground
    }

    /// The standard keyboard button shadow color.
    static func keyboardButtonShadow(
        for colorScheme: ColorScheme
    ) -> Self {
        .keyboardButtonShadow
    }

    /// The standard dark keyboard button background color.
    static func keyboardDarkButtonBackground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardDarkButtonBackgroundForColorSchemeBug :
            .keyboardDarkButtonBackground
    }

    /// The standard dark keyboard button foreground color.
    static func keyboardDarkButtonForeground(
        for colorScheme: ColorScheme
    ) -> Self {
        colorScheme.isDark ?
            .keyboardDarkButtonForegroundForDarkAppearance :
            .keyboardDarkButtonForeground
    }
}

private extension ColorScheme {
    
    var isDark: Bool {
        self == .dark
    }
}

#if KEYBOARDKIT_PREVIEWS // protly patch: xtool cannot expand #Preview reliably
#Preview {

    return ScrollView(.vertical) {
        VStack(spacing: 40) {
            StylePreviewHeader(title: "KeyboardKit Colors")

            LazyVGrid(columns: .preview, spacing: 20) {
                preview(for: .keyboardBackground, "keyboardBackground")
                preview(for: .keyboardBackgroundForDarkAppearance, "keyboardBackgroundForDarkAppearance")
                preview(for: .keyboardButtonBackground, "keyboardButtonBackground")
                preview(for: .keyboardButtonBackgroundForColorSchemeBug, "keyboardButtonBackgroundForColorSchemeBug")
                preview(for: .keyboardButtonBackgroundForDarkAppearance, "keyboardButtonBackgroundForDarkAppearance")
                preview(for: .keyboardButtonForeground, "keyboardButtonForeground")
                preview(for: .keyboardButtonForegroundForDarkAppearance, "keyboardButtonForegroundForDarkAppearance")
                preview(for: .keyboardButtonShadow, "keyboardButtonShadow")
                preview(for: .keyboardDarkButtonBackground, "keyboardDarkButtonBackground")
                preview(for: .keyboardDarkButtonBackgroundForColorSchemeBug, "keyboardDarkButtonBackgroundForColorSchemeBug")
                preview(for: .keyboardDarkButtonBackgroundForDarkAppearance, "keyboardDarkButtonBackgroundForDarkAppearance")
                preview(for: .keyboardDarkButtonForeground, "keyboardDarkButtonForeground")
                preview(for: .keyboardDarkButtonForegroundForDarkAppearance, "keyboardDarkButtonForegroundForDarkAppearance")
            }
        }
        .padding()
        .font(.title.weight(.regular))
    }

    func preview(for color: Color, _ name: String) -> some View {
        Button {
            print(name)
        } label: {
            HStack(spacing: 0) {
                color
                color.colorScheme(.dark)
            }
        }
        .background(Color.keyboardBackground)
        .aspectRatio(1, contentMode: .fill)
        .cornerRadius(10)
        .shadow(radius: 1, y: 1)
    }
}
#endif

struct StylePreviewHeader: View {

    let title: String

    var body: some View {
        VStack {
            Image.keyboardKit
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 100)
            Text(title)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.keyboardBackground)
        .clipShape(.rect(cornerRadius: 5))
        .shadow(radius: 1, y: 1)
    }
}

private extension Array where Element == GridItem {

    static var preview: Self {
        [.init(.adaptive(minimum: 100, maximum: 120), spacing: 20)]
    }
}

// protly patch: the 9.9.1 asset catalog colors, defined in code (xtool cannot compile .xcassets).
#if canImport(UIKit)
import UIKit

enum KKColor {
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    private static func gray(_ w: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(white: w, alpha: a) }

    static let keyboardBackground = dynamic(UIColor(red: 0.835, green: 0.839, blue: 0.867, alpha: 1), gray(0.173))
    static let keyboardBackgroundForDarkAppearance = dynamic(gray(0.416), gray(0.173))
    static let keyboardButtonBackground = dynamic(hex(0xFFFFFF), hex(0x6B6B6B))
    static let keyboardButtonBackgroundForColorSchemeBug = dynamic(gray(1), gray(1, 0.3))
    static let keyboardButtonBackgroundForDarkAppearance = dynamic(hex(0x979797), hex(0x979797))
    static let keyboardButtonForeground = Color(UIColor.label)
    static let keyboardButtonForegroundForDarkAppearance = dynamic(hex(0xFFFFFF), .label)
    static let keyboardButtonShadow = dynamic(gray(0, 0.3), gray(0, 0.7))
    static let keyboardDarkButtonBackground = dynamic(hex(0xABB1BA), hex(0x474747))
    static let keyboardDarkButtonBackgroundForColorSchemeBug =
        dynamic(UIColor(red: 0.702, green: 0.718, blue: 0.753, alpha: 1), gray(1, 0.1))
    static let keyboardDarkButtonBackgroundForDarkAppearance = dynamic(hex(0x757575), hex(0x757575))
}
#endif
