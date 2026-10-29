import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Container app: setup guide, the "about me" note and a test field. A free Apple ID team gets no App Group, so
// the note reaches the keyboard through the clipboard: Copy here, then Read clipboard and Save in the keyboard.
@main
struct ProtlyApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

/// ProtlyCore's AboutMe constants, repeated because this target does not link ProtlyCore.
/// tests/about-me.test.js fails when they differ.
enum AboutMeLink {
    static let marker = "protly about me v1"
    static let cap = 1000
    static let defaultsKey = "protly.aboutMe"
}

struct SetupView: View {
    @State private var test = ""
    @AppStorage(AboutMeLink.defaultsKey) private var aboutMe = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Text("1. Settings > General > Keyboard > Keyboards > Add New Keyboard > Protly")
                    Text("2. Tap Protly and turn on Allow Full Access")
                    Text("3. Keep the Emoji keyboard")
                }
                Section {
                    TextField("Who you are, in a few facts", text: $aboutMe, axis: .vertical)
                        .lineLimit(4...12)
                        .onChange(of: aboutMe) { _, new in
                            if new.count > AboutMeLink.cap { aboutMe = String(new.prefix(AboutMeLink.cap)) }
                            copied = false
                        }
                    HStack {
                        Text("\(aboutMe.count) / \(AboutMeLink.cap)").foregroundStyle(.secondary)
                        Spacer()
                        Button(copied ? "Copied" : "Copy for the keyboard", action: copyForKeyboard)
                    }
                } header: {
                    Text("About me")
                } footer: {
                    Text("Translate and Polish send this note with your draft. To update the keyboard: tap Copy for the keyboard, tap the Test field below, tap Read clipboard in the protly bar, Allow Paste, then Save. Copy an empty note to clear it.")
                }
                Section("Test") {
                    TextField("Type here", text: $test, axis: .vertical)
                }
            }
            .navigationTitle("Protly")
        }
    }

    private func copyForKeyboard() {
        let text = AboutMeLink.marker + "\n" + aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        // Local only (no Universal Clipboard) and gone after 10 minutes, so the note does not linger.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)]
        )
        copied = true
    }
}
