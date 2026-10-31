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

/// The northprot brand (design D3, `src/ui/tokens.css.js`): ink on paper in light mode, paper on ink in dark mode.
/// Repeated here because this target does not link the keyboard's.
enum Brand {
    static let paperHex = 0xF5F0E6
    static let inkHex = 0x1A1F2E
    static let paper = color(paperHex)
    static let ink = color(inkHex)
    /// Secondary text, placeholders and field rules. System `.secondary` is 3.3:1 on paper; ink at 72% is 6.1:1 on
    /// paper and paper at 72% is 8.1:1 on ink.
    static let secondaryOpacity = 0.72
    static let radius: CGFloat = 8
    static let sectionSpacing: CGFloat = 40
    static let groupSpacing: CGFloat = 16
    static let readableWidth: CGFloat = 600

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : paper }
    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? paper : ink }
    static func secondary(_ scheme: ColorScheme) -> Color { text(scheme).opacity(secondaryOpacity) }

    private static func color(_ hex: Int) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

struct SetupView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var test = ""
    @AppStorage(AboutMeLink.defaultsKey) private var aboutMe = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.sectionSpacing) {
                VStack(alignment: .leading, spacing: Brand.groupSpacing) {
                    SectionTitle("Setup")
                    Text("1. Settings > General > Keyboard > Keyboards > Add New Keyboard > Protly")
                    Text("2. Tap Protly and turn on Allow Full Access")
                    Text("3. Keep the Emoji keyboard")
                }
                VStack(alignment: .leading, spacing: Brand.groupSpacing) {
                    SectionTitle("About me")
                    TextField("Who you are, in a few facts", text: $aboutMe,
                              prompt: Text("Who you are, in a few facts").foregroundStyle(Brand.secondary(scheme)),
                              axis: .vertical)
                        .lineLimit(4...12)
                        .onChange(of: aboutMe) { _, new in
                            // Scalars, as AboutMe counts: combining marks must not hide inside one character.
                            if new.unicodeScalars.count > AboutMeLink.cap {
                                aboutMe = String(String.UnicodeScalarView(new.unicodeScalars.prefix(AboutMeLink.cap)))
                            }
                            copied = false
                        }
                        .modifier(RuledField())
                    HStack {
                        Text("\(aboutMe.unicodeScalars.count) / \(AboutMeLink.cap)")
                            .monospacedDigit()
                            .foregroundStyle(Brand.secondary(scheme))
                        Spacer()
                        Button(copied ? "Copied" : "Copy for the keyboard", action: copyForKeyboard)
                    }
                    Text("Translate and Polish send this note with your draft. To update the keyboard: tap Copy for the keyboard, tap the Test field below, tap Read clipboard in the protly bar, Allow Paste, then Save. Copy an empty note to clear it.")
                        .foregroundStyle(Brand.secondary(scheme))
                }
                VStack(alignment: .leading, spacing: Brand.groupSpacing) {
                    SectionTitle("Test")
                    TextField("Type here", text: $test,
                              prompt: Text("Type here").foregroundStyle(Brand.secondary(scheme)), axis: .vertical)
                        .modifier(RuledField())
                }
            }
            .padding()
            .frame(maxWidth: Brand.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Brand.text(scheme))
        .tint(Brand.text(scheme))
        .background { Brand.background(scheme).ignoresSafeArea() }
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

/// A section title in the system monospaced design, echoing the extension's mono font without bundling one.
private struct SectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title).font(.title2.bold()).fontDesign(.monospaced)
    }
}

/// Fields lose the Form's grouped background on the paper, so they get a visible 1 pt rule.
private struct RuledField: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(12)
            .overlay {
                RoundedRectangle(cornerRadius: Brand.radius).strokeBorder(Brand.secondary(scheme), lineWidth: 1)
            }
    }
}
