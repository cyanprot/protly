import ProtlyCore
import UIKit

// Sprint 2 spike: proves the extension loads, ProtlyCore runs inside it, and measures what the host apps allow.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private let status = UILabel()
    private var markedStep = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        status.font = .systemFont(ofSize: 13)
        status.numberOfLines = 3
        status.text = "protly spike"
        let actions: [(String, Selector)] = [
            ("안녕", #selector(typeKorean)),
            ("Marked", #selector(typeMarked)),
            ("Context", #selector(showContext)),
            ("Clipboard", #selector(readClipboard)),
            ("API", #selector(callAPI)),
            ("Next", #selector(nextKeyboard)),
        ]
        let row = UIStackView(arrangedSubviews: actions.map { title, action in
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        })
        row.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [status, row])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(equalToConstant: 216),
        ])
    }

    @objc private func typeKorean() {
        textDocumentProxy.insertText(Hangul.compose("dkssud".map { KeyEvent($0) }).text)
    }

    // Steps through a syllable being composed, the way the real keyboard will show it.
    @objc private func typeMarked() {
        let steps = ["ㅇ", "아", "안", "안ㄴ", "안녀", "안녕"]
        if markedStep < steps.count {
            let s = steps[markedStep]
            textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
            markedStep += 1
            status.text = "marked: \(s) (tap again)"
        } else {
            textDocumentProxy.unmarkText()
            markedStep = 0
            status.text = "unmarked"
        }
    }

    @objc private func showContext() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let selected = textDocumentProxy.selectedText ?? ""
        status.text = "before \(before.count), after \(after.count), selected \(selected.count); full access \(hasFullAccess)"
    }

    @objc private func readClipboard() {
        let text = UIPasteboard.general.string ?? ""
        status.text = "clipboard \(text.count) chars, changeCount \(UIPasteboard.general.changeCount)"
    }

    @objc private func callAPI() {
        status.text = "calling..."
        Task { @MainActor in status.text = await Spike.ping() }
    }

    @objc private func nextKeyboard() { advanceToNextInputMode() }
}
