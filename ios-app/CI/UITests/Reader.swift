import UIKit
import Vision
import XCTest

/// What Vision read in a region: lines in reading order (top to bottom, then left to right) and each word with its
/// box in points, so a panel button is tapped where its label is drawn (plan Task 2.3).
struct Seen {
    let lines: [String]
    let words: [(text: String, rect: CGRect)]

    /// The lines joined with single spaces (a panel's wrapped sentence reads as one).
    var text: String {
        lines.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func contains(_ phrase: String) -> Bool {
        text.contains(phrase.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
    }

    /// The lowest word equal to `label` inside `band`: a button, not the same word in the panel's text. Case does
    /// not count: Vision reads the semibold Insert as "insert" (run 40).
    func word(_ label: String, in band: CGRect) -> CGRect? {
        words.filter {
            $0.text.caseInsensitiveCompare(label) == .orderedSame && band.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY))
        }
            .max { $0.rect.midY < $1.rect.midY }?.rect
    }
}

/// Reads text from screenshots with Vision inside the UI test (plan Task 1.2): what only shows on screen, such as
/// the bar's slot labels. The field's own text is read through XCUITest instead (exact).
///
/// `selfTest()` is the positive control: Vision must read "Polish" and Hangul drawn by the test itself, so an empty
/// slot reading means an empty slot and not a broken OCR. Without it (`works` false) label checks fall back to a
/// saved crop and RECORD (plan Task 1.2 step 3).
@MainActor
final class Reader {
    private let driver: Driver
    /// Vision read the self-test's English word.
    private(set) var works = false
    /// Vision read the self-test's Hangul.
    private(set) var readsHangul = false

    static let languages = ["ko-KR", "en-US"]

    /// The languages for reading a label that names `word` (keyboard-ui 001: the center pill shows the target's
    /// endonym, such as "Русский" or "日本語"). Vision's Korean model reads Hangul and Latin only: run ec69307-50
    /// dropped a whole Cyrillic panel line under `languages`. A Cyrillic or Japanese word is read with its own model
    /// first, English second; everything else with `languages`.
    static func labelLanguages(_ word: String) -> [String] {
        let scalars = word.unicodeScalars
        if scalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { return ["ru-RU", "en-US"] }
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }) {
            return ["ja-JP", "en-US"]
        }
        return Self.languages
    }

    init(driver: Driver) {
        self.driver = driver
    }

    private func log(_ line: String) {
        driver.log(line)
    }

    /// The languages Vision offers for `.accurate` text recognition here.
    func supportedLanguages() -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        do {
            return try request.supportedRecognitionLanguages().joined(separator: ",")
        } catch {
            return "error: \(error)"
        }
    }

    /// Draws "Polish 안녕하세요" in white on the keyboard's dark green and reads it back.
    @discardableResult
    func selfTest() -> [String]? {
        let size = CGSize(width: 900, height: 150)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0, green: 0.22, blue: 0.13, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 51), .foregroundColor: UIColor.white,
            ]
            ("Polish  안녕하세요" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: attrs)
        }
        guard let cg = image.cgImage else {
            log("ocr self-test: no image")
            return nil
        }
        let lines = recognize(cg, label: "self-test")
        let all = (lines ?? []).joined(separator: " ")
        works = all.contains("Polish")
        readsHangul = all.contains("안녕하세요")
        log("ocr self-test: works \(works), hangul \(readsHangul)")
        return lines
    }

    /// Text lines in `rect` (points) of `shot`, left to right, NFC; nil when Vision failed (not when it found nothing).
    func text(in rect: CGRect, of shot: XCUIScreenshot, points: CGFloat, label: String,
              languages: [String] = Reader.languages) -> [String]? {
        guard let c = cropped(rect, of: shot, points: points, label: label) else { return nil }
        return recognize(c.image, label: label, languages: languages)
    }

    /// The text in `rect` read again from contrast-stretched crops: the crop's luminance spread over the full range
    /// at twice the size, light on dark ("dark") and inverted ("light"). For a dim label: keyboard-ui 001 dims a
    /// flip that is not a listed word, and Vision read the dim jamo-only "ㅗ디ㅣㅐ" as "-]T" (run 49f47b2-62).
    func contrastTexts(in rect: CGRect, of shot: XCUIScreenshot, points: CGFloat, label: String)
        -> [(name: String, lines: [String]?)] {
        guard let c = cropped(rect, of: shot, points: points, label: label) else { return [] }
        var reads: [(name: String, lines: [String]?)] = []
        for (name, invert) in [("dark", false), ("light", true)] {
            let image = Self.stretched(c.image, invert: invert)
            reads.append((name: name, lines: image.flatMap { recognize($0, label: "\(label) \(name)") }))
        }
        return reads
    }

    /// Gray, twice the size, luminance stretched from the crop's darkest to its lightest pixel (inverted on request).
    static func stretched(_ image: CGImage, invert: Bool) -> CGImage? {
        let w = image.width * 2, h = image.height * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h)
        var lo: UInt8 = 255, hi: UInt8 = 0
        for i in 0..<(w * h) {
            lo = min(lo, px[i])
            hi = max(hi, px[i])
        }
        guard hi > lo else { return nil }
        let span = Double(hi - lo)
        for i in 0..<(w * h) {
            let v = UInt8((Double(px[i] - lo) / span * 255).rounded())
            px[i] = invert ? 255 - v : v
        }
        return ctx.makeImage()
    }

    /// Lines in reading order and word boxes (points) in `rect` of `shot`; nil when Vision failed.
    func read(in rect: CGRect, of shot: XCUIScreenshot, points: CGFloat, label: String, quiet: Bool = false) -> Seen? {
        guard let c = cropped(rect, of: shot, points: points, label: label),
              let observations = observe(c.image, label: label) else { return nil }
        let px = c.pixels, scale = c.scale
        // Vision boxes are normalized with the origin at the bottom left of the crop.
        func toPoints(_ b: CGRect) -> CGRect {
            CGRect(x: (px.minX + b.minX * px.width) / scale, y: (px.minY + (1 - b.maxY) * px.height) / scale,
                   width: b.width * px.width / scale, height: b.height * px.height / scale)
        }
        // Reading order: rows (2% of the crop's height) from the top, then left to right.
        func row(_ o: VNRecognizedTextObservation) -> Int { Int(((1 - o.boundingBox.midY) * 50).rounded(.down)) }
        let ordered = observations.sorted { (row($0), $0.boundingBox.minX) < (row($1), $1.boundingBox.minX) }
        var lines: [String] = []
        var words: [(text: String, rect: CGRect)] = []
        for o in ordered {
            guard let top = o.topCandidates(1).first else { continue }
            lines.append(top.string.precomposedStringWithCanonicalMapping)
            top.string.enumerateSubstrings(in: top.string.startIndex..., options: .byWords) { word, range, _, _ in
                guard let word, let box = try? top.boundingBox(for: range)?.boundingBox else { return }
                words.append((text: word.precomposedStringWithCanonicalMapping, rect: toPoints(box)))
            }
        }
        if !quiet { log("ocr \(label): \(lines.map { String(reflecting: $0) }.joined(separator: " "))") }
        return Seen(lines: lines, words: words)
    }

    /// The crop of `rect` (points), its rect in pixels and the pixels per point.
    private func cropped(_ rect: CGRect, of shot: XCUIScreenshot, points: CGFloat, label: String)
        -> (image: CGImage, pixels: CGRect, scale: CGFloat)? {
        guard let cg = shot.image.cgImage, points > 0 else {
            log("ocr \(label): no image")
            return nil
        }
        let scale = CGFloat(cg.width) / points
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !px.isEmpty, let crop = cg.cropping(to: px) else {
            log("ocr \(label): empty crop \(rect)")
            return nil
        }
        return (crop, px, scale)
    }

    private func observe(_ image: CGImage, label: String,
                         languages: [String] = Reader.languages) -> [VNRecognizedTextObservation]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log("ocr \(label): Vision error \(error)")
            return nil
        }
        return request.results ?? []
    }

    func recognize(_ image: CGImage, label: String, languages: [String] = Reader.languages) -> [String]? {
        guard let results = observe(image, label: label, languages: languages) else { return nil }
        let observations = results.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.precomposedStringWithCanonicalMapping }
        log("ocr \(label): \(lines.map { String(reflecting: $0) }.joined(separator: " "))")
        return lines
    }
}
