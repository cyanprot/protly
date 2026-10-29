import ProtlyCore
import SwiftUI

/// The predictive bar: Apple's three equal slots (the protly key is in the bottom row).
/// Left: the other reading of the word being typed or just typed (tap flips). Center: Undo after an Insert,
/// else the action that fits the field (Translate / Polish), else "Read clipboard" when new text was copied.
/// Right: a fix (typo, contraction, text replacement) or a completion for the word being typed; tap takes it.
struct ProtlyBar: View {
    @ObservedObject var mode: ProtlyMode
    let flip: () -> Void
    let act: (ActionMode?) -> Void   // nil = the protly key: whatever fits the field
    let undo: () -> Void
    let pick: () -> Void

    var body: some View {
        // Each slot sits on Color.clear: an `if` with no else draws nothing, and an empty slot must still take
        // its third (Sprint 5 phone check: with no flip, Translate slid to the left quarter).
        HStack(spacing: 0) {
            ZStack { Color.clear; left }
            ZStack { Color.clear; center }
            ZStack { Color.clear; right }
        }
        .lineLimit(1)
        .frame(height: ProtlyGeometry.toolbarHeight)
        .padding(.top, ProtlyGeometry.topBand)
    }

    @ViewBuilder
    private var left: some View {
        if let alt = mode.alternative, !alt.isEmpty {
            Button(action: flip) { Text("\u{201C}\(alt)\u{201D}") }
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var right: some View {
        if let s = mode.suggestion {
            Button(s, action: pick).foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var center: some View {
        if mode.canUndo {
            Button("Undo", action: undo).foregroundStyle(.primary)
        } else if let draft = mode.draftMode {
            Button(draft == .out ? "Translate" : "Polish") { act(draft) }.foregroundStyle(.primary)
        } else if mode.clipboardIsNew {
            Button("Read clipboard") { act(.in) }.foregroundStyle(.primary)
        }
    }
}
