import ProtlyCore
import SwiftUI

/// The result card's state besides the streamed text (ResultFeed). Changes once at the first text and once at the
/// end of the call, and when Replace finds the field changed.
struct CardState: Equatable {
    enum Phase: Equatable {
        case streaming, done, failed
    }

    /// The call's id (StripState.call): a new call is a new card.
    let call: Int
    let action: ActionMode
    /// The header: the call as the bar labeled it ("→ English").
    let label: BarAction
    /// What the read returned, for Replace and the field check.
    let original: String
    let isSelection: Bool
    /// systemUptime when the card appeared: its buttons ignore taps for AboutMe.saveDelay, because the keys were live
    /// until now and a typing thumb is right there.
    let shownAt: Double
    var phase: Phase = .streaming
    /// The field changed during the call (P10): the result stays, only Copy is offered.
    var copyOnly = false

    /// Replace for Translate and Polish, Insert for Read; only once done and while the field is as read.
    var primary: String? {
        guard phase == .done, !copyOnly else { return nil }
        return action == .in ? "Insert" : "Replace"
    }
}

/// The glass card over the keys (design Part 3, steps 2 to 6): the header, the text arriving with a steady caret,
/// the back translation once done, an error line under kept text, and the buttons pinned below.
struct ResultCard: View {
    let card: CardState
    let feed: ResultFeed
    /// true when the copy was made (a tap in the first AboutMe.saveDelay seconds is dropped).
    let copy: () -> Bool
    let replace: () -> Void
    let close: () -> Void
    let retry: (ActionMode) -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView {
                // Only this view reads the streamed text: a delta redraws it, not the header or the buttons.
                CardText(feed: feed, phase: card.phase, copyOnly: card.copyOnly)
            }
            // Follows new text without a scrollTo per delta.
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .bottom, spacing: 8) { buttons }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(12)
        .modifier(CardGlass())
        .padding(.horizontal, 6)
        .contentShape(.rect)  // the side strips must not pass taps to the keys underneath
        .accessibilityIdentifier("protly-card")  // the simulator checks find the card's texts by it (not spoken)
    }

    /// Symbol, arrow and title as in the pill: separate views, so a right-to-left endonym cannot reorder them.
    private var header: some View {
        HStack(spacing: 4) {
            if let symbol = card.label.symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            if card.label.arrow { Text(verbatim: "→") }
            Text(card.label.title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// One row when it fits; else two rows, never one per button, so the text above keeps room at large text sizes.
    /// The labels stop growing at xxxLarge: the card's height is the key area's, whatever the text size.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                closeButton
                Spacer(minLength: 0)
                retryButton
                copyButton
                primaryButton
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    closeButton
                    Spacer(minLength: 0)
                    retryButton
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    copyButton
                    primaryButton
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closeButton: some View {
        button(card.action == .in ? "Done" : "Cancel", action: close)
    }

    @ViewBuilder
    private var retryButton: some View {
        if let error = feed.failed, error.canRetry {
            button("Retry") { retry(card.action) }
        }
    }

    private var copyButton: some View {
        button(copied ? "Copied" : "Copy") {
            if copy() { copied = true }
        }
        .disabled(card.phase == .streaming)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let primary = card.primary {
            button(primary, action: replace).fontWeight(.semibold)
        } else if card.phase == .streaming {
            // Keeps the row's layout while the text arrives.
            button(card.action == .in ? "Insert" : "Replace") {}.disabled(true)
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            // The keys were live until the card appeared: a tap in its first moment is a typing thumb.
            guard AboutMe.canSave(shownAt: card.shownAt, now: ProcessInfo.processInfo.systemUptime) else { return }
            action()
        } label: {
            Text(title)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
    }
}

/// The card's text: the translation (with a steady caret while it streams, dimmed when kept after an error), the back
/// translation once done, and the error or field-changed line.
private struct CardText: View {
    let feed: ResultFeed
    let phase: CardState.Phase
    let copyOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phase == .streaming {
                // The caret is text, not an icon, and never blinks. VoiceOver reads the text without it.
                let caret = Text(verbatim: "▍").foregroundStyle(.secondary)
                Text("\(feed.partial)\(caret)").font(.body).accessibilityLabel(Text(feed.partial))
            } else {
                Text(feed.partial).font(.body).foregroundStyle(phase == .failed ? .secondary : .primary)
            }
            if phase == .done, !feed.back.isEmpty {
                Text(feed.back).font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = feed.failed {
                Text(error.message).font(.footnote).foregroundStyle(.secondary)
            } else if copyOnly {
                Text("The text changed while this ran. Copy the result instead.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How the panel layer shows the card (design Part 3, step 2): it grows down from the strip over the keys, and under
/// Reduce Motion it only crossfades. ProtlyRoot animates `visible`; the layer stays mounted, so nothing leaves with a
/// transition (the ghost card).
struct CardReveal: ViewModifier {
    let visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.94, anchor: .top)
    }
}

/// System glass on iOS 26, the regular material before it (the target is iOS 17). No hand-rolled blur.
struct CardGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }
}
