import KeyboardKit
import SwiftUI

/// Apple's keyboard on the iPhone 13 Pro, portrait, measured from screenshots on 2026-10-28
/// (docs/ios-keyboard-notes.md, "Sprint 2: KeyboardKit"). KeyboardKit's iOS 26 values are 56/47.
enum ProtlyGeometry {
    static let rowPitch: CGFloat = 54
    static let keyHeight: CGFloat = 43
    /// Band above the first row is host padding + this + the first row's top inset. Tuned from screenshots.
    static let toolbarHeight: CGFloat = 29
    /// KeyboardKit's standard is -2. Tuned from screenshots.
    static let bottomInset: CGFloat = -11
}

final class ProtlyLayoutService: KeyboardLayout.iPhoneLayoutService {
    override func itemSizeHeight(for action: KeyboardAction, row: Int, index: Int, context: KeyboardContext) -> CGFloat {
        guard context.interfaceOrientation.isPortrait else {
            return super.itemSizeHeight(for: action, row: row, index: index, context: context)
        }
        return ProtlyGeometry.rowPitch
    }

    override func itemInsets(for action: KeyboardAction, row: Int, index: Int, context: KeyboardContext) -> EdgeInsets {
        let base = super.itemInsets(for: action, row: row, index: index, context: context)
        guard context.interfaceOrientation.isPortrait else { return base }
        switch action {
        case .characterMargin, .none: return base
        default:
            let v = (ProtlyGeometry.rowPitch - ProtlyGeometry.keyHeight) / 2
            return EdgeInsets(top: v, leading: base.leading, bottom: v, trailing: base.trailing)
        }
    }
}

extension KeyboardLayout.InputSet {
    /// Dubeolsik on the QWERTY grid: same 10/9/7 rows, so key widths match English exactly.
    static let dubeolsik = Self(rows: [
        .init(lowercased: "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", uppercased: "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ"),
        .init(chars: "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ"),
        .init(chars: "ㅋㅌㅊㅍㅠㅜㅡ"),
    ])

    /// Korean keycaps while shift is only automatic (sentence start): Korean has no capitals,
    /// and automatic shift never selects ㅃ (ProtlyCore `Dubeolsik.jamo(for:)`).
    static let dubeolsikPlain = Self(rows: [
        .init(chars: "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ"),
        .init(chars: "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ"),
        .init(chars: "ㅋㅌㅊㅍㅠㅜㅡ"),
    ])
}
