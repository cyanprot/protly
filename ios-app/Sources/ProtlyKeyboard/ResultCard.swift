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
                VStack(alignment: .leading, spacing: 8) {
                    text
                    if card.phase == .done, !feed.back.isEmpty {
                        Text(feed.back).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let error = feed.failed {
                        Text(error.message).font(.footnote).foregroundStyle(.secondary)
                    } else if card.copyOnly {
                        Text("The text changed while this ran. Copy the result instead.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    /// Symbol, arrow and title as in the pill: separate views, so a right-to-left endonym cannot reorder them.
    private var header: some View {
        HStack(spacing: 4) {
            if let symbol = card.label.symbol { Image(systemName: symbol).imageScale(.small) }
            if card.label.arrow { Text(verbatim: "→") }
            Text(card.label.title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// While streaming, a steady caret (text, no blink) after the text. Kept text after an error is dimmed.
    @ViewBuilder
    private var text: some View {
        if card.phase == .streaming {
            let caret = Text(verbatim: "▍").foregroundStyle(.secondary)
            Text("\(feed.partial)\(caret)").font(.body)
        } else {
            Text(feed.partial).font(.body).foregroundStyle(card.phase == .failed ? .secondary : .primary)
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttonRow(stacked: false) }
            VStack(spacing: 0) { buttonRow(stacked: true) }
        }
    }

    @ViewBuilder
    private func buttonRow(stacked: Bool) -> some View {
        button(card.action == .in ? "Done" : "Cancel", stacked: stacked, action: close)
        if !stacked { Spacer(minLength: 0) }
        if let error = feed.failed, error.canRetry {
            button("Retry", stacked: stacked) { retry(card.action) }
        }
        button(copied ? "Copied" : "Copy", stacked: stacked) {
            if copy() { copied = true }
        }
        .disabled(card.phase == .streaming)
        if let primary = card.primary {
            button(primary, stacked: stacked, action: replace).fontWeight(.semibold)
        } else if card.phase == .streaming {
            // Keeps the row's layout while the text arrives.
            button(card.action == .in ? "Insert" : "Replace", stacked: stacked) {}.disabled(true)
        }
    }

    private func button(_ title: String, stacked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // The keys were live until the card appeared: a tap in its first moment is a typing thumb.
            guard AboutMe.canSave(shownAt: card.shownAt, now: ProcessInfo.processInfo.systemUptime) else { return }
            action()
        } label: {
            Text(title)
                .padding(.horizontal, 8)
                .frame(maxWidth: stacked ? .infinity : nil, minHeight: 44)
                .contentShape(.rect)
        }
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
