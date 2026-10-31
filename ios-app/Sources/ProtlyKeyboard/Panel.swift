import ProtlyCore
import SwiftUI

/// What the panel shows in place of the keys. Never changes the keyboard height. While a call runs the keys stay and
/// the bar shows the progress strip (StripState); the result card opens at the first text.
enum PanelState: Equatable {
    /// The result card; its text is in ResultFeed.
    case card(CardState)
    /// A failure before any call (nothing copied, Paste not allowed, part of the field unread), with Retry.
    case failed(String, retry: ActionMode)
    /// A clipboard note waiting for Save (insert) or Cancel (close). shownAt: systemUptime when it appeared.
    case confirmNote(String, shownAt: Double)
    /// A message with no action, such as the about-me note being saved.
    case notice(String)
}

struct PanelView: View {
    let state: PanelState
    let feed: ResultFeed
    let insert: () -> Void
    let copy: () -> Bool
    let close: () -> Void
    let retry: (ActionMode) -> Void

    var body: some View {
        if case .card(let card) = state {
            ResultCard(card: card, feed: feed, copy: copy, replace: insert, close: close, retry: retry)
                .id(card.call)
        } else {
            message
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .card:
                EmptyView()
            case let .failed(message, mode):
                Spacer()
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
                buttons(primary: ("Retry", { retry(mode) }), closeLabel: "Cancel")
            case .confirmNote(let note, _):
                ScrollView {
                    Text(AboutMe.confirmText(for: note)).font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                buttons(primary: ("Save", insert), closeLabel: "Cancel")
            case .notice(let message):
                Spacer()
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
                buttons(primary: nil, closeLabel: "Done")
            }
        }
        .font(.body)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(12)
        .modifier(CardGlass())
        .padding(.horizontal, 6)
        .contentShape(.rect)  // the side strips must not pass taps to the keys underneath
    }

    @ViewBuilder
    private func buttons(primary: (String, () -> Void)?, closeLabel: String) -> some View {
        HStack {
            Button(closeLabel, action: close).frame(minHeight: 44)
            Spacer()
            if let (label, action) = primary {
                Button(label, action: action).fontWeight(.semibold).frame(minHeight: 44)
            }
        }
    }
}
