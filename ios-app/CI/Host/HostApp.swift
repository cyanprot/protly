import SwiftUI

/// CI-only host for the keyboard screenshots (ios-app/CI/README.md): one multi-line field, focused on launch,
/// on one solid color that measure.py knows (`HOST_BG`). `-prefill "text"` on the command line puts text in it.
/// The phone checks use `Clear` (empties the field without keys) and `Dismiss` (the field loses focus, which hides
/// the keyboard), both in the top-right corner, away from the field and the center column measure.py samples.
@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup { HostView() }
    }
}

struct HostView: View {
    @State private var text = UserDefaults.standard.string(forKey: "prefill") ?? ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // measure.py HOST_BG = (32, 160, 96). It samples this at 30% of the screen height.
            Color(red: 32 / 255, green: 160 / 255, blue: 96 / 255).ignoresSafeArea()
            // The field stays in the top-left so the center column below it is only background.
            TextField("", text: $text, axis: .vertical)
                .lineLimit(1...3)
                .focused($focused)
                .accessibilityIdentifier("field")
                .foregroundStyle(.white)
                .frame(width: 200, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, 24)
            VStack(alignment: .trailing, spacing: 16) {
                Button("Clear") { text = "" }
                    .accessibilityIdentifier("clear")
                Button("Dismiss") { focused = false }
                    .accessibilityIdentifier("dismiss")
            }
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .padding(.top, 24)
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // focus right at launch is sometimes dropped
            focused = true
        }
    }
}
