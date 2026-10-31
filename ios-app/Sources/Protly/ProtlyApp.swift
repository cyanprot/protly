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
    @State private var guide: Guide?
    @FocusState private var testFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.sectionSpacing) {
                Hero()
                TurnOnSection()
                TryItSection(test: $test, guide: $guide, focused: $testFocused)
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

private struct Hero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("protly").font(.largeTitle.bold()).fontDesign(.monospaced)
            Text("Write Korean, send English.").font(.title3)
        }
        .padding(.top, Brand.groupSpacing)
    }
}

/// F2: the two switches in Settings, why each is needed, and what leaves the phone. The app cannot read whether the
/// keyboard or Full Access is on (no App Group), so it shows no status.
private struct TurnOnSection: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.groupSpacing) {
            SectionTitle("Turn on Protly")
            NumberedRow(number: 1) {
                Text("Add the Protly keyboard").font(.headline)
                Text("In Settings, tap Keyboards and turn on Protly, so the globe key can switch to it.")
                    .foregroundStyle(Brand.secondary(scheme))
            }
            NumberedRow(number: 2) {
                Text("Turn on Allow Full Access").font(.headline)
                Text("Translate, Polish and Read need the network and the clipboard.")
                    .foregroundStyle(Brand.secondary(scheme))
            }
            // Right after Full Access, where iOS shows its warning.
            VStack(alignment: .leading, spacing: 4) {
                Text("What Protly sends").font(.headline)
                Text("Only when you tap an action, and only to the model API: Translate and Polish send the field's text and your About me note; Read sends the copied text. Keystrokes are never sent. Words the keyboard learns stay on this phone.")
                    .foregroundStyle(Brand.secondary(scheme))
            }
            Button("Open Settings", systemImage: "gear", action: openSettings)
                .buttonStyle(PillButtonStyle())
        }
    }

    /// Protly's own page in Settings, which holds its Keyboards switches.
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// A: the test field, three samples that fill it, and the three things only typed keys can show.
private struct TryItSection: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var test: String
    @Binding var guide: Guide?
    let focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.groupSpacing) {
            SectionTitle("Try it")
            // Without the switch the field opens with Apple's keyboard and nothing below works.
            Text("Switch to Protly with the \(Image(systemName: "globe")) key under the keyboard, and back the same way.")
            // iOS 17 has no wrapping stack: the chips go in a column when a row does not fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { SampleChips(fill: fill) }
                VStack(alignment: .leading, spacing: 8) { SampleChips(fill: fill) }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Type here", text: $test,
                          prompt: Text("Type here").foregroundStyle(Brand.secondary(scheme)), axis: .vertical)
                    .focused(focused)
                    .modifier(RuledField())
                if case let .sample(sample)? = guide {
                    sample.hint
                }
            }
            // Plain rows, not buttons: these come only from keys typed on the keyboard, so a button would do nothing.
            VStack(alignment: .leading, spacing: 8) {
                NumberedRow(number: 1) { Text("Type `dkssud`, then tap the left slot.") }
                NumberedRow(number: 2) { Text("Type `teh`, then tap the right slot.") }
                NumberedRow(number: 3) {
                    Text("After a Replace, tap \(Image(systemName: "arrow.uturn.backward")) Undo.")
                }
            }
        }
    }

    private func fill(_ sample: Sample) {
        test = sample.text
        guide = .sample(sample)
        focused.wrappedValue = true
    }
}

/// What the line under the test field says.
private enum Guide: Equatable {
    /// A chip filled the field: the action to tap.
    case sample(Sample)
}

/// A sample for the test field: the chip's title, the text it puts in the field and the hint under the field.
/// Headline first.
private enum Sample: CaseIterable {
    case korean, english, prefixed

    var title: LocalizedStringKey {
        switch self {
        case .korean: "Translate"
        case .english: "Polish"
        case .prefixed: "Other languages"
        }
    }

    var text: String {
        switch self {
        case .korean: "오늘 고마워"
        case .english: "thank you for invite me, i realy enjoyed it"
        case .prefixed: "ru: 고마워"
        }
    }

    /// The symbol the keyboard's bar shows for the action, embedded in the line.
    var hint: Text {
        let sparkles = Image(systemName: "sparkles")
        return switch self {
        case .korean: Text("Tap \(sparkles) → English.")
        case .english: Text("Tap \(sparkles) Polish.")
        case .prefixed: Text("Tap \(sparkles) → Русский.")
        }
    }
}

private struct SampleChips: View {
    let fill: (Sample) -> Void

    var body: some View {
        ForEach(Sample.allCases, id: \.self) { sample in
            Button(sample.title) { fill(sample) }
                .buttonStyle(ChipButtonStyle())
        }
    }
}

/// One step of a numbered list: the number in the title's monospaced design, then its lines.
private struct NumberedRow<Content: View>: View {
    let number: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").fontDesign(.monospaced)
            VStack(alignment: .leading, spacing: 4) { content }
        }
    }
}

/// The brand pill (D3), as in the keyboard's bar: ink with paper text in light mode, paper with ink text in dark.
private struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.background(scheme))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Brand.text(scheme), in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A chip as in the extension (`.pl-chip`): a capsule with a 1 pt rule, at least 44 pt tall.
private struct ChipButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? Brand.text(scheme).opacity(0.12) : .clear, in: .capsule)
            .overlay { Capsule().strokeBorder(Brand.secondary(scheme), lineWidth: 1) }
            .contentShape(.capsule)
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
