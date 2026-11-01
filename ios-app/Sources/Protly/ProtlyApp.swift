import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Container app: one guide screen (design Part 2): turn on the keyboard, try it, and the "about me" note. A free
// Apple ID team gets no App Group, so the note reaches the keyboard through the clipboard: Copy here, then Read
// and Save in the keyboard.
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
    /// Quiet rules around a group (the extension's `--pl-rule`); text never uses it.
    static let ruleOpacity = 0.18
    static let radius: CGFloat = 8
    static let sectionSpacing: CGFloat = 40
    static let groupSpacing: CGFloat = 16
    static let readableWidth: CGFloat = 600

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : paper }
    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? paper : ink }
    static func secondary(_ scheme: ColorScheme) -> Color { text(scheme).opacity(secondaryOpacity) }
    static func rule(_ scheme: ColorScheme) -> Color { text(scheme).opacity(ruleOpacity) }

    private static func color(_ hex: Int) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

struct SetupView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var test = ""
    @State private var guide: Guide?
    @FocusState private var testFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.sectionSpacing) {
                    Hero()
                    TurnOnSection()
                    TryItSection(test: $test, guide: $guide, focused: $testFocused)
                    AboutMeSection(guide: $guide) { showSaveSteps(proxy) }
                }
                .padding()
                .frame(maxWidth: Brand.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Brand.text(scheme))
        .tint(Brand.text(scheme))
        .background { Brand.background(scheme).ignoresSafeArea() }
    }

    /// A2: the note reaches the keyboard through the test field, so after the copy the field is emptied (the bar
    /// offers Read only on an empty field), focused and shown with the steps that save the note.
    private func showSaveSteps(_ proxy: ScrollViewProxy) {
        test = ""
        guide = .saveNote
        testFocused = true
        // Top, not center: the scroll runs before the keyboard rises, and a centered field ends up under it.
        withAnimation(reduceMotion ? nil : .default) {
            proxy.scrollTo(TryItSection.fieldID, anchor: .top)
        }
    }
}

/// A2: the note, its counter and Copy for the keyboard. A free Apple ID team gets no App Group, so the note reaches
/// the keyboard through the clipboard.
private struct AboutMeSection: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(AboutMeLink.defaultsKey) private var aboutMe = ""
    @State private var copied = false
    @Binding var guide: Guide?
    /// After the copy: point at the test field and the steps that save the note there.
    let showSaveSteps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.groupSpacing) {
            SectionTitle("About me")
            Text("Translate and Polish send this note with your draft.")
                .foregroundStyle(Brand.secondary(scheme))
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
                    if guide == .saveNote { guide = nil }  // the steps would save the old note
                }
                .modifier(RuledField())
            // At accessibility sizes the pill goes under the counter instead of squeezing beside it.
            let row = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
            row {
                Text("\(aboutMe.unicodeScalars.count) / \(AboutMeLink.cap)")
                    .monospacedDigit()
                    .foregroundStyle(Brand.secondary(scheme))
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy for the keyboard", action: copy)
                    .buttonStyle(PillButtonStyle())
            }
            Text("Copy an empty note to clear it from the keyboard.")
                .foregroundStyle(Brand.secondary(scheme))
        }
    }

    private func copy() {
        copyForKeyboard()
        showSaveSteps()
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
            Text("Polish and translate as you type.").font(.title3)
        }
        .padding(.top, Brand.groupSpacing)
    }
}

/// F2: the three setup steps (add the keyboard, allow Full Access, keep Apple's Emoji), why each is needed, and
/// what leaves the phone. The app cannot read whether the keyboard or Full Access is on (no App Group), so it shows
/// no status.
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
                // Right after the Full Access reason, where iOS shows its warning.
                Text("What Protly sends").font(.headline).padding(.top, 8)
                Text("Only when you tap an action, and only to the model API: Translate and Polish send the field's text and your About me note; Read sends the copied text. Keystrokes are never sent. Words the keyboard learns stay on this phone.")
                    .foregroundStyle(Brand.secondary(scheme))
            }
            // The in-row emoji key is the protly key; iOS's own key under the keyboard reaches Emoji.
            NumberedRow(number: 3) {
                Text("Keep Apple's Emoji keyboard").font(.headline)
                Text("Protly has no emoji keys: switch to Apple's Emoji with the key under the keyboard.")
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
    static let fieldID = "test-field"

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.groupSpacing) {
            SectionTitle("Try it")
            // Without the switch the field opens with Apple's keyboard and nothing below works.
            Text("Switch to Protly with the key under the keyboard (\(Image(systemName: "globe")), or \(Image(systemName: "face.smiling")) when Protly and Emoji are your only keyboards), and back the same way.")
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
                switch guide {
                case let .sample(sample)?: sample.hint
                case .saveNote?: SaveNoteSteps()
                case nil: EmptyView()
                }
            }
            .id(Self.fieldID)
            // Plain rows, not buttons: these come only from keys typed on the keyboard, so a button would do nothing.
            VStack(alignment: .leading, spacing: 8) {
                NumberedRow(number: 1) { Text("Type `teh`, then tap the right slot.") }
                NumberedRow(number: 2) {
                    Text("After a Replace, tap \(Image(systemName: "arrow.uturn.backward")) Undo.")
                }
                NumberedRow(number: 3) { Text("Writing Korean? Type `dkssud`: it turns into 안녕 on its own. The left slot flips a word back.") }
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
    /// About me was copied: the steps that save it in the keyboard.
    case saveNote
}

/// The numbered banner under the test field after Copy for the keyboard.
private struct SaveNoteSteps: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Then, on the Protly keyboard:").font(.headline)
            NumberedRow(number: 1) { Text("Tap \(Image(systemName: "doc.on.clipboard")) Read in the bar.") }
            NumberedRow(number: 2) { Text("Tap Allow Paste.") }
            NumberedRow(number: 3) { Text("Tap Save.") }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: Brand.radius).strokeBorder(Brand.rule(scheme), lineWidth: 1)
        }
    }
}

/// A sample for the test field: the chip's title, the text it puts in the field and the hint under the field.
/// Written for an English speaker: Polish first; Korean is the one other language Translate reads so far.
private enum Sample: CaseIterable {
    case english, korean

    var title: LocalizedStringKey {
        switch self {
        case .english: "Polish"
        case .korean: "Translate Korean"
        }
    }

    var text: String {
        switch self {
        case .english: "thank you for invite me, i realy enjoyed it"
        case .korean: "오늘 고마워"
        }
    }

    /// The words the keyboard's bar shows for the action.
    var hint: Text {
        switch self {
        case .english: Text("Tap Polish in the bar.")
        case .korean: Text("Tap → English in the bar.")
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
