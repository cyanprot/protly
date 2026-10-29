import KeyboardKit
import ProtlyCore
import SwiftUI
import UIKit

@objc(KeyboardViewController)
final class KeyboardViewController: KeyboardInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setup(for: KeyboardApp(name: "Protly")) { _ in }
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { controller in
            KeyboardView(
                state: controller.state,
                services: controller.services,
                buttonContent: { $0.view },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in SpikeBar(proxy: controller.textDocumentProxy) }
            )
        }
    }
}

struct SpikeBar: View {
    let proxy: UITextDocumentProxy
    @State private var status = "protly"

    var body: some View {
        HStack {
            Text(status).font(.footnote).lineLimit(1)
            Spacer()
            Button("안녕") { proxy.insertText(Hangul.compose("dkssud".map { KeyEvent($0) }).text) }
            Button("API") { Task { status = await Spike.ping() } }
        }
        .padding(.horizontal, 12)
        .frame(height: 45)
    }
}
