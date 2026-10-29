import ProtlyCore
import SwiftUI

/// What the panel shows in place of the keys. Never changes the keyboard height.
enum PanelState: Equatable {
    case loading(ActionMode)
    case result(ActionMode, ActionResult, original: String, isSelection: Bool)
    case failed(String, retry: ActionMode)
    /// A clipboard note waiting for Save (insert) or Cancel (close).
    case confirmNote(String)
    /// A message with no action, such as the about-me note being saved.
    case notice(String)
}

struct PanelView: View {
    let state: PanelState
    let insert: () -> Void
    let close: () -> Void
    let retry: (ActionMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .loading(let mode):
                Spacer()
                HStack { Spacer(); ProgressView(); Text(title(mode)).foregroundStyle(.secondary); Spacer() }
                Spacer()
                buttons(primary: nil, closeLabel: "Cancel")
            case let .result(mode, result, _, _):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.translation).font(.system(size: 17))
                        if !result.backTranslation.isEmpty {
                            Text(result.backTranslation).font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                buttons(primary: mode == .in ? nil : ("Insert", insert), closeLabel: mode == .in ? "Done" : "Cancel")
            case let .failed(message, mode):
                Spacer()
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
                buttons(primary: ("Retry", { retry(mode) }), closeLabel: "Cancel")
            case .confirmNote(let note):
                ScrollView {
                    Text(AboutMe.confirmText(for: note)).font(.system(size: 15))
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())  // the side strips must not pass taps to the keys underneath
    }

    private func title(_ mode: ActionMode) -> String {
        switch mode {
        case .in: return "Reading"
        case .out: return "Translating"
        case .fix: return "Polishing"
        }
    }

    @ViewBuilder
    private func buttons(primary: (String, () -> Void)?, closeLabel: String) -> some View {
        HStack {
            Button(closeLabel, action: close)
            Spacer()
            if let (label, action) = primary {
                Button(label, action: action).fontWeight(.semibold)
            }
        }
        .font(.system(size: 17))
    }
}
