import UIKit
import Vision
import XCTest

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
    func text(in rect: CGRect, of shot: XCUIScreenshot, points: CGFloat, label: String) -> [String]? {
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
        return recognize(crop, label: label)
    }

    func recognize(_ image: CGImage, label: String) -> [String]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = Self.languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log("ocr \(label): Vision error \(error)")
            return nil
        }
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.precomposedStringWithCanonicalMapping }
        log("ocr \(label): \(lines.map { String(reflecting: $0) }.joined(separator: " "))")
        return lines
    }
}
