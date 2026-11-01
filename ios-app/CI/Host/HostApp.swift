import Combine
import SwiftUI
import UIKit
import WebKit

/// CI-only host for the keyboard screenshots (ios-app/CI/README.md). `-screen <name>` on the command line picks a
/// screen; every screen is offline:
/// - none: one multi-line field, focused on launch, on one solid color that measure.py knows (`HOST_BG`).
///   `-prefill "text"` puts text in it.
/// - `uikit`: a UITextView (typing-fixes 004: the edit menu and the space trackpad) whose selection, marked text and
///   first and last word frames are published as accessibility values for XCUITest.
/// - `web`: a dark web composer (typing-fixes 004: Return in web fields, the word's ink on a dark page) in a WKWebView,
///   from the bundled web-composer.html. Its state is published as an accessibility value and every DOM event is
///   appended to Documents/web-events.txt, which run-shots.sh copies into the run folder.
/// Every screen has `Clear` (empties the field without keys) and `Dismiss` (the field loses focus, which hides the
/// keyboard) in the top-right corner, away from the field and the center column measure.py samples.
@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            switch UserDefaults.standard.string(forKey: "screen") ?? "" {
            case "web": WebComposerScreen()
            case "uikit": TextViewScreen()
            default: HostView()
            }
        }
    }
}

/// measure.py HOST_BG = (32, 160, 96). It samples this at 30% of the screen height, so every screen keeps its content
/// above that line and the center column below it is only background.
let hostBackground = Color(red: 32 / 255, green: 160 / 255, blue: 96 / 255)

struct HostView: View {
    @State private var text = UserDefaults.standard.string(forKey: "prefill") ?? ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            hostBackground.ignoresSafeArea()
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

/// A small caption whose accessibility value carries one reading for XCUITest (exact, unlike OCR).
struct Probe: View {
    let id: String
    let value: String

    var body: some View {
        Text("\(id) \(value)")
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: 90, alignment: .trailing)
            .accessibilityIdentifier(id)
            .accessibilityValue(value)
    }
}

// MARK: - UIKit text view (`-screen uikit`)

/// A UITextView whose accessibility value is always its text: an empty one reads "" (Driver.clearField), not nil.
final class ProbeTextView: UITextView {
    override var accessibilityValue: String? {
        get { text ?? "" }
        set {}
    }
}

@MainActor
final class TextViewModel: ObservableObject {
    /// `location,length` of the selection, in UTF-16 units.
    @Published var selection = ""
    @Published var marked = ""
    /// `x,y,w,h` in screen points: where a double-tap selects that word.
    @Published var firstWord = ""
    @Published var lastWord = ""
    weak var textView: UITextView?

    func clear() {
        textView?.text = ""
        refresh()
    }

    func dismiss() {
        textView?.resignFirstResponder()
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    /// Polled (5 times a second): the keyboard moves the caret through the text input system, which does not always
    /// call the delegate.
    func refresh() {
        guard let tv = textView else { return }
        let r = tv.selectedRange
        update(\.selection, "\(r.location),\(r.length)")
        update(\.marked, tv.markedTextRange == nil ? "no" : "yes")
        let words = Self.wordRanges(tv.text ?? "")
        update(\.firstWord, words.first.flatMap { Self.frame(of: $0, in: tv) } ?? "")
        update(\.lastWord, words.last.flatMap { Self.frame(of: $0, in: tv) } ?? "")
    }

    private func update(_ key: ReferenceWritableKeyPath<TextViewModel, String>, _ value: String) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    /// Runs of characters that are not a space, a tab or a line break, in UTF-16 units.
    static func wordRanges(_ s: String) -> [NSRange] {
        let ns = s as NSString
        var ranges: [NSRange] = []
        var start: Int?
        for i in 0..<ns.length {
            let c = ns.character(at: i)
            let blank = c == 0x20 || c == 0x0A || c == 0x09 || c == 0xA0
            if blank, let s0 = start {
                ranges.append(NSRange(location: s0, length: i - s0))
                start = nil
            } else if !blank && start == nil {
                start = i
            }
        }
        if let s0 = start { ranges.append(NSRange(location: s0, length: ns.length - s0)) }
        return ranges
    }

    static func frame(of range: NSRange, in tv: UITextView) -> String? {
        guard let a = tv.position(from: tv.beginningOfDocument, offset: range.location),
              let b = tv.position(from: a, offset: range.length),
              let textRange = tv.textRange(from: a, to: b) else { return nil }
        let rect = tv.firstRect(for: textRange)
        guard !rect.isNull, !rect.isInfinite, rect.width > 0 else { return nil }
        let r = tv.convert(rect, to: nil)
        return String(format: "%.1f,%.1f,%.1f,%.1f", r.minX, r.minY, r.width, r.height)
    }
}

struct TextViewField: UIViewRepresentable {
    let model: TextViewModel

    func makeUIView(context: Context) -> ProbeTextView {
        let tv = ProbeTextView()
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        // Apple's keyboard (menu-0) then types exactly the keys the test taps.
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.accessibilityIdentifier = "field"
        model.textView = tv
        return tv
    }

    func updateUIView(_ uiView: ProbeTextView, context: Context) {}
}

struct TextViewScreen: View {
    @StateObject private var model = TextViewModel()
    private let tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            hostBackground.ignoresSafeArea()
            TextViewField(model: model)
                .frame(width: 200, height: 80)
                .padding(.leading, 16)
                .padding(.top, 24)
            VStack(alignment: .trailing, spacing: 10) {
                Button("Clear") { model.clear() }
                    .accessibilityIdentifier("clear")
                Button("Dismiss") { model.dismiss() }
                    .accessibilityIdentifier("dismiss")
                Probe(id: "sel", value: model.selection)
                Probe(id: "marked", value: model.marked)
                Probe(id: "first-word", value: model.firstWord)
                Probe(id: "last-word", value: model.lastWord)
            }
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .padding(.top, 24)
        }
        .onReceive(tick) { _ in model.refresh() }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // focus right at launch is sometimes dropped
            model.focus()
        }
    }
}

// MARK: - Web composer (`-screen web`)

@MainActor
final class WebModel: NSObject, ObservableObject, WKScriptMessageHandler {
    /// The page's JSON state: each field's text, the sent and submitted lists, the text when Return arrived, a trace.
    @Published var state = ""
    /// JSON {"composer": [x, y, w, h], ...} in screen points.
    @Published var rects = ""
    weak var webView: WKWebView?
    private let events = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("web-events.txt")

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else {
            append("host: malformed message \(message.body)")
            return
        }
        switch kind {
        case "event":
            if let line = body["line"] as? String { append(line) }
        case "state":
            if let json = body["json"] as? String, json != state { state = json }
            if let r = body["rects"] as? [String: Any] { publish(r) }
        default:
            append("host: unknown message kind \(kind)")
        }
    }

    func clear() {
        webView?.evaluateJavaScript("clearAll()") { [weak self] _, error in
            if let error { self?.append("host: clearAll() failed: \(error)") }
        }
    }

    func dismiss() {
        webView?.evaluateJavaScript("document.activeElement && document.activeElement.blur()", completionHandler: nil)
        webView?.endEditing(true)
    }

    func fail(_ why: String) {
        state = "{\"error\":\"\(why)\"}"
    }

    /// Page coordinates (CSS px from the viewport's top-left) to screen points: the page neither scrolls nor zooms.
    private func publish(_ r: [String: Any]) {
        guard let web = webView else { return }
        var out: [String: [Double]] = [:]
        for (name, v) in r {
            guard let a = (v as? [NSNumber])?.map({ $0.doubleValue }), a.count == 4 else { continue }
            let rect = web.convert(CGRect(x: a[0], y: a[1], width: a[2], height: a[3]), to: nil)
            out[name] = [rect.minX, rect.minY, rect.width, rect.height].map { (Double($0) * 10).rounded() / 10 }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8), s != rects else { return }
        rects = s
    }

    private func append(_ line: String) {
        guard let url = events else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

struct WebComposer: UIViewRepresentable {
    let model: WebModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(model, name: "protly")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.accessibilityIdentifier = "web"
        model.webView = web
        if let url = Bundle.main.url(forResource: "web-composer", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let model = model
            Task { @MainActor in model.fail("web-composer.html is not in the bundle") }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebComposerScreen: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            hostBackground.ignoresSafeArea()
            // Ends about 240 pt down, above measure.py's background sample at 30% of the height.
            WebComposer(model: model)
                .frame(width: 280, height: 184)
                .padding(.top, 8)
            VStack(alignment: .trailing, spacing: 10) {
                Button("Clear") { model.clear() }
                    .accessibilityIdentifier("clear")
                Button("Dismiss") { model.dismiss() }
                    .accessibilityIdentifier("dismiss")
                Probe(id: "web-state", value: model.state)
                Probe(id: "web-rects", value: model.rects)
            }
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .padding(.top, 24)
        }
    }
}
