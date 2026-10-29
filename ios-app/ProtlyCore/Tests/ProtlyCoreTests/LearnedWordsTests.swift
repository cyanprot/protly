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

    func testLimitDropsTheLeastUsedAndJSONKeepsCounts() throws {
        var l = LearnedWords()
        l.learn("keep", as: .english)
        l.learn("keep", as: .english)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for i in 0..<LearnedWords.limit {
            l.learn("x" + String(letters[i / 26 % 26]) + String(letters[i % 26]) + String(letters[i / 676]), as: .english)
        }
        XCTAssertEqual(l.size(.english), LearnedWords.limit)
        XCTAssertEqual(l.count(of: "keep", in: .english), 2)
        let back = try JSONDecoder().decode(LearnedWords.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.count(of: "keep", in: .english), 2)
        XCTAssertEqual(back.size(.english), LearnedWords.limit)
    }
}
