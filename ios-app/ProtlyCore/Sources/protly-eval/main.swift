import Foundation
import ProtlyCore

// Word-level accuracy of LanguageDetector on a corpus, typed the way a user would type it.
// Usage: swift run -c release protly-eval <corpus-dir>
// Corpus files: one sentence per line. Each token is labeled by its script: Hangul -> korean,
// ASCII letters -> english, anything else (digits, mixed) is skipped.

struct Token { let keys: [KeyEvent]; let truth: Language; let text: String }

func tokens(of line: String) -> [Token] {
    var out: [Token] = []
    var sentenceStart = true
    for raw in line.split(separator: " ") {
        let word = String(raw).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        defer { sentenceStart = raw.last.map { ".?!".contains($0) } ?? false }
        if word.isEmpty { continue }
        if let k = KeyEncoder.keys(forHangul: word) {
            out.append(Token(keys: k, truth: .korean, text: word))
        } else if let k = KeyEncoder.keys(forLatin: word, sentenceStart: sentenceStart) {
            out.append(Token(keys: k, truth: .english, text: word))
        }
    }
    return out
}

struct Score {
    var total = 0, correct = 0, flips = 0, flippedWords = 0
    var errors: [String: Int] = [:]
}

func evaluate(_ detector: LanguageDetector, _ lines: [String]) -> [Language: Score] {
    var scores: [Language: Score] = [.korean: Score(), .english: Score()]
    var previous: Language? = nil  // like the keyboard: the last language carries over to the next message
    for line in lines {
        for t in tokens(of: line) {
            let got = detector.decide(t.keys, complete: true, previous: previous)
            var s = scores[t.truth]!
            s.total += 1
            if got == t.truth { s.correct += 1 } else { s.errors[t.text, default: 0] += 1 }
            // Stability while typing: how often the shown language changes across prefixes.
            var shown: Language? = nil, changes = 0
            for n in 1...t.keys.count {
                let d = n == t.keys.count ? got : detector.decide(Array(t.keys.prefix(n)), complete: false, previous: previous)
                if let p = shown, p != d { changes += 1 }
                shown = d
            }
            s.flips += changes
            if changes > 0 {
                s.flippedWords += 1
                if ProcessInfo.processInfo.environment["FLIPS"] != nil {
                    let trace = (1...t.keys.count).map { n -> String in
                        let d = n == t.keys.count ? got : detector.decide(Array(t.keys.prefix(n)), complete: false, previous: previous)
                        return d == .korean ? "K" : "E"
                    }.joined()
                    print("FLIP", t.text, trace, "prev:", previous.map { "\($0)" } ?? "nil")
                }
            }
            scores[t.truth] = s
            previous = got
        }
    }
    return scores
}

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: protly-eval <corpus-dir>")
    exit(2)
}
let dir = URL(fileURLWithPath: args[1])
let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }.sorted()

for bonus in [0.0, 1.0, 2.0, 3.0, 4.0] {
    let detector = try LanguageDetector.bundled(priorBonus: bonus)
    print("== priorBonus \(bonus)")
    for f in files {
        let lines = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        let scores = evaluate(detector, lines)
        for lang in [Language.korean, .english] {
            let s = scores[lang]!
            guard s.total > 0 else { continue }
            let acc = 100.0 * Double(s.correct) / Double(s.total)
            let flipped = 100.0 * Double(s.flippedWords) / Double(s.total)
            let top = s.errors.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)x\($0.value)" }
            print(String(format: "%@ %@: %d words, accuracy %.2f%%, words that flip while typing %.1f%%",
                         f, "\(lang)", s.total, acc, flipped), "| top errors:", top.joined(separator: " "))
        }
    }
}
