import Foundation

// Word frequencies keyed by KEY STRING, sorted for prefix search. English keys are the lowercase word;
// Korean keys are Dubeolsik.koreanKeyString of the word, so a half-typed syllable still prefix-matches.

public struct WordList: Sendable {
    private let keys: [String]
    private let counts: [Int]
    public let total: Double

    public init(entries: [(key: String, count: Int)]) {
        var merged: [String: Int] = [:]
        for e in entries { merged[e.key, default: 0] += e.count }
        let sorted = merged.sorted { $0.key < $1.key }
        keys = sorted.map(\.key)
        counts = sorted.map(\.value)
        total = Double(max(1, counts.reduce(0, +)))
    }

    /// FrequencyWords format: "word count" per line.
    static func parse(_ text: String) -> [(word: String, count: Int)] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2, let n = Int(parts[1]) else { return nil }
            return (String(parts[0]), n)
        }
    }

    public static func english(_ text: String) -> WordList {
        WordList(entries: parse(text).compactMap { w in
            let lower = w.word.lowercased()
            guard !lower.isEmpty, lower.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
            return (lower, w.count)
        })
    }

    public static func korean(_ text: String) -> WordList {
        WordList(entries: parse(text).compactMap { w in
            guard let k = KeyEncoder.keys(forHangul: w.word) else { return nil }
            return (Dubeolsik.koreanKeyString(k), w.count)
        })
    }

    public static func bundled(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public var count: Int { keys.count }

    private func lowerBound(_ key: String) -> Int {
        var lo = 0, hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public func frequency(of key: String) -> Int {
        let i = lowerBound(key)
        return i < keys.count && keys[i] == key ? counts[i] : 0
    }

    /// Highest count among words starting with `prefix` (0 when none). Scans at most `limit` entries.
    public func bestFrequency(prefix: String, limit: Int = 5000) -> Int {
        var i = lowerBound(prefix), best = 0, seen = 0
        while i < keys.count, seen < limit, keys[i].hasPrefix(prefix) {
            best = max(best, counts[i])
            i += 1
            seen += 1
        }
        return best
    }
}
