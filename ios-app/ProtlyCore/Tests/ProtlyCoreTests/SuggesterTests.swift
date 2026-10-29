import XCTest
@testable import ProtlyCore

final class SuggesterTests: XCTestCase {
    let lists = LanguageDetector(
        english: WordList(entries: [("the", 50_000), ("there", 30_000), ("they", 20_000), ("happy", 5_000),
                                    ("do", 60_000), ("don", 40_000), ("tea", 900), ("plus", 30_000), ("th", 6_000),
                                    ("about", 40_000), ("ago", 30_000), ("tehran", 900)]),
        korean: WordList(entries: [("dkssud", 500), ("dkssudgktpdy", 300), ("rmfo", 400)]),  // 안녕 안녕하세요 그래
        priorBonus: 2.0
    )
    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testEnglishCompletionIsTheMostFrequentLongerWord() {
        let s = Suggester()
        XCTAssertEqual(s.completion(keys("th"), as: .english, lists: lists), "the")
        XCTAssertEqual(s.completion(keys("the"), as: .english, lists: lists), "there")
        XCTAssertEqual(s.completion(keys("Th"), as: .english, lists: lists), "The")
        XCTAssertEqual(s.completion(keys("do"), as: .english, lists: lists), "don't")  // stem of don't
        XCTAssertNil(s.completion(keys("xy"), as: .english, lists: lists))
    }

    func testKoreanCompletionFollowsKeys() {
        let s = Suggester()
        XCTAssertEqual(s.completion(keys("dkssu"), as: .korean, lists: lists), "안녕")      // 안녀: the last syllable is still open
        XCTAssertEqual(s.completion(keys("dkssudg"), as: .korean, lists: lists), "안녕하세요")  // 안녕ㅎ
        XCTAssertNil(s.completion(keys("gkr"), as: .korean, lists: lists))                 // 학: nothing listed
    }

    func testLearnedWordsRankFirst() {
        var s = Suggester()
        s.learned.learn("Theo", as: .english)
        XCTAssertEqual(s.completion(keys("th"), as: .english, lists: lists), "Theo")
        s.learned.learn("안녕들", as: .korean)
        XCTAssertEqual(s.completion(keys("dkssu"), as: .korean, lists: lists), "안녕들")
    }

    func testOneTypoSuggestsAFix() {
        let s = Suggester()
        XCTAssertEqual(s.fix(keys("teh"), as: .english, lists: lists), "the")    // swapped; "tehran" is too rare to wait for
        XCTAssertEqual(s.fix(keys("thw"), as: .english, lists: lists), "the")    // neighbour key
        XCTAssertEqual(s.fix(keys("hapy"), as: .english, lists: lists), "happy") // missed key
        XCTAssertEqual(s.fix(keys("Teh"), as: .english, lists: lists), "The")
        XCTAssertNil(s.fix(keys("te"), as: .english, lists: lists))              // too short to guess
        XCTAssertNil(s.fix(keys("tez"), as: .english, lists: lists))             // only "tea", too rare
        XCTAssertNil(s.fix(keys("dkn"), as: .english, lists: lists))             // only "don", a stem, never a fix
        XCTAssertNil(s.fix(keys("teh"), as: .korean, lists: lists))              // no Korean typo fixes
        XCTAssertNil(s.fix(keys("pls"), as: .english, lists: lists))             // slang, not "plus"
        XCTAssertNil(s.fix(keys("thq"), as: .english, lists: lists))             // "th" is too short a target
        // Still being typed, not a typo: "about" starts with abo, so no "ago".
        XCTAssertNil(s.fix(keys("abo"), as: .english, lists: lists))
        XCTAssertEqual(s.completion(keys("abo"), as: .english, lists: lists), "about")
    }

    func testKnownWordsGetNoFix() {
        var s = Suggester()
        XCTAssertNil(s.fix(keys("tea"), as: .english, lists: lists))  // in the list
        s.learned.learn("thw", as: .english)
        XCTAssertNil(s.fix(keys("thw"), as: .english, lists: lists))  // learned
    }

    func testAContactNameIsAKnownWordNotAFix() {
        // A contact name maps to itself: "will" must never become "Will", nor be treated as a typo.
        var s = Suggester()
        s.lexicon = ["will": "Will", "teh": "teh"]
        XCTAssertNil(s.fix(keys("will"), as: .english, lists: lists))
        XCTAssertNil(s.fix(keys("teh"), as: .english, lists: lists))
    }

    func testContractionsAndTextReplacements() {
        var s = Suggester()
        XCTAssertEqual(s.fix(keys("i"), as: .english, lists: lists), "I")
        XCTAssertEqual(s.fix(keys("dont"), as: .english, lists: lists), "don't")
        XCTAssertEqual(s.fix(keys("Im"), as: .english, lists: lists), "I'm")
        XCTAssertNil(s.fix(keys("I"), as: .english, lists: lists))
        s.lexicon = ["omw": "On my way!", "ㅎㅇ": "안녕하세요"]
        XCTAssertEqual(s.fix(keys("omw"), as: .english, lists: lists), "On my way!")
        XCTAssertEqual(s.fix(keys("gd"), as: .korean, lists: lists), "안녕하세요")
    }

    func testAShortcutIsFoundInEitherReading() {
        // After a Korean word, the keys of "ty" compose as 쇼; after an English word, ㅎㅇ reads "gd".
        var s = Suggester()
        s.lexicon = ["ty": "Thank you", "ㅎㅇ": "안녕하세요"]
        XCTAssertEqual(s.fix(keys("ty"), as: .korean, lists: lists), "Thank you")
        XCTAssertEqual(s.fix(keys("gd"), as: .english, lists: lists), "안녕하세요")
        s.lexicon["쇼"] = "show time"  // the current reading wins
        XCTAssertEqual(s.fix(keys("ty"), as: .korean, lists: lists), "show time")
    }
}
