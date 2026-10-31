import ProtlyCore
import SwiftUI

/// The bar while a call runs, or after it failed before any text arrived (keyboard-ui 003). The keys stay live.
struct StripState: Equatable {
    /// Fresh per call, a Retry included: restarts the 8 s line.
    let call: Int
    let action: ActionMode
    /// What the strip names: the call as the bar would label it.
    let label: BarAction
    /// The call failed before any text: the error line replaces the label, the glow stops.
    var error: ActionError?
}

/// The progress strip in the bar's band (design Part 3, step 1): the operation and its target, an `xmark`, and a thin
/// glow along the bottom edge while the call runs. A tap on the strip itself does nothing (B10). After 8 s a second
/// line says it is still going (P5).
struct ProgressStrip: View {
    let state: StripState
    /// The keyboard's appearance (KeyboardKit's context), as for the pill.
    let scheme: ColorScheme
    let close: () -> Void
    let retry: (ActionMode) -> Void

    @State private var slow = false

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                if let error = state.error {
                    Text(error.message)
                        .font(.subheadline)
                        .lineLimit(2)
                } else {
                    label.font(.subheadline.weight(.medium))
                    if slow, let line = state.label.slowLine {
                        Text(line).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let error = state.error, error.canRetry {
                Button { retry(state.action) } label: {
                    Text("Retry").fontWeight(.semibold).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
            }
            Button("Cancel", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .frame(height: BarSlotStyle.rowHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            // Only while the call runs; removing the view stops its animation (done, cancel, viewWillDisappear).
            if state.error == nil {
                StripGlow(color: Brand.pillFill(scheme))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .frame(height: ProtlyGeometry.topBand + ProtlyGeometry.toolbarHeight)
        // A fresh call restarts the line; the state changes only when the sleep finished, never after a cancel.
        .task(id: state.call) {
            slow = false
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            slow = true
        }
    }

    /// "Translating → English…": separate views, so a right-to-left endonym cannot reorder them.
    private var label: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(state.label.progressVerb ?? "")
                if state.label.arrow {
                    Text(verbatim: "→")
                    Text(state.label.title)
                }
            }
            Text(verbatim: "…")
        }
    }
}

/// A thin band of the brand color sweeping along the strip's bottom edge, never under the text: one gradient
/// offset, no blur. The only gradient on the keyboard, and only while a call runs (D3). Still under Reduce Motion.
private struct StripGlow: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        LinearGradient(colors: [color.opacity(0), color.opacity(0.9), color.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            // From off the left edge to off the right; centered and still under Reduce Motion.
            .visualEffect { [sweep, reduceMotion] content, proxy in
                content.offset(x: reduceMotion ? 0 : (sweep ? proxy.size.width : -proxy.size.width))
            }
            .frame(height: 2)
            .clipped()
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}
