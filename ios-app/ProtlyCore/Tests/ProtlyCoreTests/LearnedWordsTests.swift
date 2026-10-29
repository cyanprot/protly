import Foundation
import XCTest
@testable import ProtlyCore

final class LearnedWordsTests: XCTestCase {
    func testWordsAreKeyedLikeTheLists() {
        var l = LearnedWords()
        l.learn("iPhone", as: .english)
        l.learn("걍", as: .korean)
        l.learn("걍", as: .korean)
        l.learn("don't", as: .english)  // not typable as one word: ignored
        XCTAssertEqual(l.count(of: "iphone", in: .english), 1)
        XCTAssertEqual(l.count(of: "rid", in: .korean), 2)
        XCTAssertEqual(l.count(of: "rid", in: .english), 0)
        XCTAssertTrue(l.hasPrefix("ri", in: .korean))
        XCTAssertFalse(l.hasPrefix("ri", in: .english))
        XCTAssertEqual(l.changes, 3)
    }

    func testCompletionIsTheMostUsedLongerWord() {
        var l = LearnedWords()
        l.learn("Theo", as: .english)
        l.learn("Theo", as: .english)
        l.learn("thermos", as: .english)
        XCTAssertEqual(l.completion(of: "th", in: .english), "Theo")
        XCTAssertEqual(l.completion(of: "ther", in: .english), "thermos")
        XCTAssertNil(l.completion(of: "theo", in: .english))  // not longer than what was typed
    }

    func testUnlearnTakesBackOneLearn() {
        var l = LearnedWords()
        l.learn("걍", as: .korean)
        l.learn("걍", as: .korean)
        l.unlearn("걍", as: .korean)
        XCTAssertEqual(l.count(of: "rid", in: .korean), 1)
        l.unlearn("걍", as: .korean)
        XCTAssertEqual(l.count(of: "rid", in: .korean), 0)
        XCTAssertFalse(l.hasPrefix("ri", in: .korean))
        l.unlearn("걍", as: .korean)  // nothing left to take back: no change
        XCTAssertEqual(l.changes, 4)
    }

    func testLongWordsAreNotLearned() {
        var l = LearnedWords()
        let max = LearnedWords.maxKeyLength
        l.learn(String(repeating: "a", count: max + 1), as: .english)
        l.learn(String(repeating: "a", count: max), as: .english)
        XCTAssertEqual(l.size(.english), 1)
        XCTAssertEqual(l.changes, 1)
        // Korean counts keys, not syllables: 안 is three keys (dks).
        XCTAssertEqual(LearnedWords.key(of: String(repeating: "안", count: 10), in: .korean)?.count, 30)
        XCTAssertNil(LearnedWords.key(of: String(repeating: "안", count: 11), in: .korean))
    }

    /// Distinct a-z words: "x" plus three letters.
    private func filler(_ i: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return "x" + String(letters[i / 26 % 26]) + String(letters[i % 26]) + String(letters[i / 676])
    }

    func testLimitDropsTheLeastUsedAndJSONKeepsCounts() throws {
        // Full: limit - 1 words used twice and one used once. A new word pushes out the one used once.
        var l = LearnedWords()
        for i in 0..<(LearnedWords.limit - 1) {
            l.learn(filler(i), as: .english)
            l.learn(filler(i), as: .english)
        }
        l.learn("victim", as: .english)
        XCTAssertEqual(l.size(.english), LearnedWords.limit)
        l.learn("newcomer", as: .english)
        XCTAssertEqual(l.count(of: "newcomer", in: .english), 1)
        XCTAssertEqual(l.count(of: "victim", in: .english), 0)
        XCTAssertTrue((0..<(LearnedWords.limit - 1)).allSatisfy { l.count(of: filler($0), in: .english) == 2 })
        XCTAssertEqual(l.size(.english), LearnedWords.limit)
        let back = try JSONDecoder().decode(LearnedWords.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.count(of: filler(0), in: .english), 2)
        XCTAssertEqual(back.count(of: "newcomer", in: .english), 1)
        XCTAssertEqual(back.size(.english), LearnedWords.limit)
    }

    func testDecodingDropsBadEntriesAndTrimsToTheLimit() throws {
        // The saved JSON is read back as untrusted: over-long keys and counts <= 0 go, and past the limit the
        // least used go first.
        let long = String(repeating: "a", count: LearnedWords.maxKeyLength + 1)
        let english = (0..<LearnedWords.limit).map { "\"\(filler($0))\": {\"text\": \"\(filler($0))\", \"count\": 2}" }
            + ["\"once\": {\"text\": \"once\", \"count\": 1}", "\"\(long)\": {\"text\": \"\(long)\", \"count\": 5}"]
        let json = """
            {"english": {\(english.joined(separator: ", "))},
             "korean": {"rid": {"text": "걍", "count": 3}, "zero": {"text": "x", "count": 0},
                        "minus": {"text": "y", "count": -4}}}
            """
        let l = try JSONDecoder().decode(LearnedWords.self, from: Data(json.utf8))
        XCTAssertEqual(l.size(.english), LearnedWords.limit)
        XCTAssertEqual(l.count(of: "once", in: .english), 0)
        XCTAssertEqual(l.count(of: long, in: .english), 0)
        XCTAssertEqual(l.count(of: filler(0), in: .english), 2)
        XCTAssertEqual(l.size(.korean), 1)
        XCTAssertEqual(l.count(of: "rid", in: .korean), 3)
        XCTAssertEqual(l.completion(of: "ri", in: .korean), "걍")
    }
}
