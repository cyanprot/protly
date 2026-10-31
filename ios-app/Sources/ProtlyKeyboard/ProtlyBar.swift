import ProtlyCore
import SwiftUI

/// The predictive bar: Apple's three equal slots (the protly key is in the bottom row), each a button the full third
/// of the width and the whole band above row 1 (BarSlotStyle), with thin dividers between them like Apple's.
/// Left: the other reading of the word being typed or just typed (tap flips), dimmed when it is not a listed word.
/// Center: the action pill (BarAction: Undo after a Replace, else the action that fits the field, else Read when new
/// text was copied). Right: a fix (typo, contraction, text replacement) or a completion for the word being typed.
/// Every label comes from ProtlyMode; the decisions behind it live in ProtlyCore.
struct ProtlyBar: View {
    @ObservedObject var mode: ProtlyMode
    /// The keyboard's appearance (KeyboardKit's context), the same source the keys use: a dark keyboard in a light
    /// app must not get an ink pill on dark glass.
    let scheme: ColorScheme
    let flip: () -> Void
    let act: (ActionMode?) -> Void
    let undo: () -> Void
    let pick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Each slot sits on Color.clear: an `if` with no else draws nothing, and an empty slot must still take
        // its third (Sprint 5 phone check: with no flip, Translate slid to the left quarter).
        HStack(spacing: 0) {
            ZStack { Color.clear; left }
            divider(visible: hasLeft && mode.center != nil)
            // The animation sits on the always-present slot: on the pill an `if let` removal would take it along
            // (no fade-out), and on the HStack the side slots would fade on every key.
            ZStack { Color.clear; center }
                .animation(.easeOut(duration: 0.15), value: mode.center)
            divider(visible: mode.center != nil && mode.suggestion != nil)
            ZStack { Color.clear; right }
        }
        .buttonStyle(BarSlotStyle())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // The whole band above row 1, not only the text row: the keyboard's height and the rows do not move.
        .frame(height: ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight)
    }

    private var hasLeft: Bool { !(mode.alternative ?? "").isEmpty }

    @ViewBuilder
    private var left: some View {
        if let alt = mode.alternative, !alt.isEmpty {
            // No quotes: in Apple's bar quotes mean "keep as typed", the opposite of a flip.
            Button(action: flip) {
                Text(alt).foregroundStyle(mode.alternativeIsWord ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder
    private var right: some View {
        if let s = mode.suggestion {
            Button(action: pick) { Text(s).foregroundStyle(.primary) }
        }
    }

    @ViewBuilder
    private var center: some View {
        if let action = mode.center {
            Button {
                if action == .undo { undo() } else { act(action.actionMode) }
            } label: {
                pill(action)
            }
            .transition(pillTransition)
        }
    }

    /// Symbol, arrow and title are separate views: a right-to-left endonym cannot reorder them.
    /// Without Full Access (F1) the pill is an outlined capsule in the label color with `lock.fill`, not a dimmed
    /// fill (about 2.5:1 on the light ink pill); a tap explains why (KeyboardViewController.act).
    private func pill(_ action: BarAction) -> some View {
        let locked = !mode.fullAccess && action != .undo
        return ZStack {
            // A change between two actions keeps the pill and only crossfades the label.
            HStack(spacing: 4) {
                Image(systemName: locked ? "lock.fill" : action.symbol).imageScale(.small)
                if action.arrow { Text(verbatim: "→") }
                Text(action.title)
            }
            .id(action)
            .transition(.opacity)
        }
        .fontWeight(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(locked ? AnyShapeStyle(.primary) : AnyShapeStyle(Brand.pillText(scheme)))
        .background(locked ? AnyShapeStyle(.clear) : AnyShapeStyle(Brand.pillFill(scheme)), in: .capsule)
        .overlay {
            Capsule().strokeBorder(locked ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear), lineWidth: 1)
        }
        .padding(.horizontal, 6)
    }

    /// In: fade and scale up (0.15 s ease-out, from the slot's animation). Out: fade only, faster. Under Reduce
    /// Motion every change is a fade.
    private var pillTransition: AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)),
            removal: .opacity.animation(.easeOut(duration: 0.1)))
    }

    /// Apple's thin divider, centered on the label row and inset from the band's top and bottom. Hidden next to an
    /// empty slot with opacity, so the slots keep their identity and width.
    private func divider(visible: Bool) -> some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5)
            .padding(.vertical, 10)
            .frame(height: BarSlotStyle.rowHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(visible ? 1 : 0)
    }
}
