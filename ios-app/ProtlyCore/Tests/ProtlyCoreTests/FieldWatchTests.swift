import XCTest
@testable import ProtlyCore

final class FieldWatchTests: XCTestCase {
    typealias O = FieldWatch.Observed
    let window = FieldWatch.ownEditWindow
    let lateEnough = 10.0  // well past the own-edit window

    /// A word 안녕 typed key by key after "오늘 ", the last write at t = 0.
    private func typed(_ states: [String] = ["안", "안ㄴ", "안녀", "안녕"], start: String = "오늘 ",
                       after: String = "") -> FieldWatch {
        FieldWatch(start: start, after: after, history: [""] + states, lastOwnEdit: 0)
    }

    private func decide(_ w: FieldWatch, _ o: O, at now: Double? = nil) -> FieldWatch.Decision {
        w.decide(o, composing: true, lastTail: nil, now: now ?? lateEnough)
    }

    // MARK: rules while a word is typed

    func testTheFieldHoldsTheWord() {
        XCTAssertEqual(decide(typed(), O(before: "오늘 안녕")), .keep)
    }

    func testASelectionAbandons() {
        // H3: a double-tap selects the word just typed. Keeping it would write the old word over the selection.
        let w = typed()
        XCTAssertEqual(decide(w, O(before: "오늘 ", selected: "안녕")), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘 안녕", selected: "안녕")), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘 안녕", selected: "안녕"), at: 0.01), .abandon)  // even in the window
    }

    func testATapInsideTheWordAbandons() {
        // 안|녕: the context before matches the state 안, but the cursor moved. The next backspace would delete 안.
        let w = typed()
        XCTAssertEqual(decide(w, O(before: "오늘 안", after: "녕")), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘 안", after: "녕"), at: 0.01), .abandon)  // even in the window
        XCTAssertEqual(decide(w, O(before: "오늘 ", after: "안녕")), .abandon)  // long-press at the word's start
    }

    func testAnAfterContextCutAtTheFarEndStillAgrees() {
        let w = typed(after: " 내일 봐. 그리고 저녁에 전화할게")
        XCTAssertEqual(decide(w, O(before: "오늘 안녕", after: " 내일 봐.")), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 안녕", after: "")), .abandon)  // moved to the end
    }

    func testAnyOtherChangeAbandonsOutsideTheWindow() {
        let w = typed()
        XCTAssertEqual(decide(w, O(before: "")), .abandon)               // the host sent and cleared the field
        XCTAssertEqual(decide(w, O(before: "오늘")), .abandon)           // the cursor moved elsewhere
        XCTAssertEqual(decide(w, O(before: "다른 글 안녕ㅎ")), .abandon)  // another field
    }

    func testHasTextIsNotUsed() {
        // WebKit reports hasText false right after each edit: with plain text it would split every word.
        XCTAssertEqual(decide(typed(), O(before: "오늘 안녕", hasText: false)), .keep)
        XCTAssertEqual(decide(typed(), O(before: "", hasText: false)), .abandon)  // a cleared field fails anyway
    }

    // MARK: a context that lags behind Protly's writes

    func testAContextShowingAnEarlierStateOfTheWordKeeps() {
        let w = typed(["안", "안ㄴ", "안녀"])
        XCTAssertEqual(decide(w, O(before: "오늘 안ㄴ")), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 안")), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 ")), .keep)  // before the first key
    }

    func testTheStateBetweenTheDeletesAndTheInsertIsInTheHistory() {
        // ㄱ to 가 deletes ㄱ, then inserts 가: a context read between the two shows the empty word.
        var w = FieldWatch(start: "오늘 ")
        w.wrote(deleting: 0, inserting: "ㄱ", at: 0)
        w.wrote(deleting: 1, inserting: "가", at: 0.05)
        XCTAssertEqual(w.history, ["", "ㄱ", "", "가"])
        XCTAssertEqual(w.expected, "오늘 가")
        XCTAssertEqual(decide(w, O(before: "오늘 ")), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 ㄱ")), .keep)
    }

    func testAFirstKeyThatReadsAContextMissingProtlysSpaceKeeps() {
        // "hello" was typed, Protly inserted " ", and the next word's first key read the stale "hello".
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "hello", at: 0)
        w.wrote(deleting: 0, inserting: " ", at: 0.1)
        w.begin(O(before: "hello"))
        XCTAssertEqual(w.start, "hello ")  // Protly's model, not the stale read
        w.wrote(deleting: 0, inserting: "ㅇ", at: 0.2)
        XCTAssertEqual(decide(w, O(before: "hello")), .keep)       // still stale
        XCTAssertEqual(decide(w, O(before: "hello ")), .keep)      // caught up with the space
        XCTAssertEqual(decide(w, O(before: "hello ㅇ")), .keep)    // caught up
        XCTAssertEqual(decide(w, O(before: "helloㅇ")), .abandon)  // not a state Protly wrote
    }

    func testAnEmptyContextKeepsOnlyInsideTheWindow() {
        let w = typed()
        XCTAssertEqual(decide(w, O(before: ""), at: window / 2), .keep)
        XCTAssertEqual(decide(w, O(before: ""), at: window * 2), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘"), at: window / 2), .keep)  // the model is trusted in the window
    }

    func testTheWindowStartsAtTheLastWrite() {
        var w = typed()
        w.wrote(deleting: 0, inserting: "ㅎ", at: 5)
        XCTAssertEqual(decide(w, O(before: ""), at: 5 + window / 2), .keep)
        XCTAssertEqual(decide(w, O(before: ""), at: 5 + window + 0.001), .abandon)
        XCTAssertEqual(decide(w, O(before: ""), at: 4), .abandon)  // a clock before the write is not in the window
    }

    // MARK: a context cut at the front

    func testALongFieldCutAtTheFrontKeeps() {
        let start = String(String(repeating: "가나다라마 ", count: 84).prefix(500))
        XCTAssertEqual(start.count, 500)
        let w = typed(start: start)
        let cut = String((start + "안녕").suffix(100))
        XCTAssertEqual(decide(w, O(before: cut)), .keep)
        XCTAssertEqual(decide(w, O(before: String((start + "안ㄴ").suffix(100)))), .keep)  // cut and lagging
        XCTAssertEqual(decide(w, O(before: String((start + "안녕ㅎ").suffix(100)))), .abandon)
    }

    func testAModelLongerThanTheContextCutAtTheFrontStillMatchesAFullerContext() {
        // The model came from a cut context; a later read shows more of the field.
        let w = typed(start: "늘 ")
        XCTAssertEqual(decide(w, O(before: "어제 오늘 안녕")), .keep)
    }

    // MARK: no word being typed

    func testWithNoWordOnlyTheFlipIsChecked() {
        let w = FieldWatch(start: "오늘 ")
        XCTAssertEqual(w.decide(O(before: "오늘 안녕 "), composing: false, lastTail: "안녕 ", now: 0), .keep)
        XCTAssertEqual(w.decide(O(before: "오늘 안녕"), composing: false, lastTail: "안녕 ", now: 0), .forgetLast)
        XCTAssertEqual(w.decide(O(before: ""), composing: false, lastTail: nil, now: 0), .keep)
        XCTAssertEqual(w.decide(O(before: "x", selected: "x"), composing: false, lastTail: nil, now: 0), .keep)
    }

    // MARK: the model

    func testBeginTakesTheContextWhenTheModelIsUnknownOrTheCursorMoved() {
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "hello ", at: 0)
        var moved = w
        moved.begin(O(before: "hel", after: "lo "))  // tapped inside "hello"
        XCTAssertEqual(moved.start, "hel")
        XCTAssertEqual(moved.after, "lo ")
        var selected = w
        selected.begin(O(before: "", selected: "hello "))
        XCTAssertEqual(selected.start, "")
        var forgotten = w
        forgotten.forget()
        XCTAssertFalse(forgotten.known)
        forgotten.begin(O(before: "hello"))
        XCTAssertEqual(forgotten.start, "hello")
        XCTAssertTrue(forgotten.known)
        var other = w
        other.begin(O(before: "something else"))
        XCTAssertEqual(other.start, "something else")
        XCTAssertEqual(other.lead, [])
    }

    func testBeginNeverTakesAnEmptyContextForLag() {
        // A chat app sent "안녕\n" and cleared the field: the next word starts in an empty field.
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "안녕", at: 0)
        w.wrote(deleting: 0, inserting: "\n", at: 0.1)
        w.begin(O(before: ""))
        XCTAssertEqual(w.start, "")
        XCTAssertEqual(w.lead, [])
    }

    func testBeginKeepsTheLongerOfAMatchingContextAndModel() {
        var w = FieldWatch(start: "늘 ")
        w.wrote(deleting: 0, inserting: "안녕 ", at: 0)
        w.begin(O(before: "어제 오늘 안녕 "))
        XCTAssertEqual(w.start, "어제 오늘 안녕 ")
        XCTAssertEqual(w.history, [""])
    }

    func testDeletesPastTheWordMoveTheStart() {
        // A backspace over the space before the next word (KeyboardKit's delete, outside a word).
        var w = FieldWatch(start: "오늘 ")
        w.wrote(deleting: 0, inserting: "안녕", at: 0)
        w.wrote(deleting: 0, inserting: " ", at: 0.1)
        w.wrote(deleting: 1, inserting: "", at: 0.2)
        XCTAssertEqual(w.expected, "오늘 안녕")
        w.wrote(deleting: 3, inserting: "", at: 0.3)  // 녕, 안, then the space before the word
        XCTAssertEqual(w.expected, "오늘")
        XCTAssertEqual(w.start, "오늘")
        w.begin(O(before: "오늘 안"))  // stale: shows the field after the first of the three deletes
        XCTAssertEqual(w.start, "오늘")
        w.wrote(deleting: 0, inserting: "ㅇ", at: 0.4)
        XCTAssertEqual(decide(w, O(before: "오늘 안")), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘ㅇ")), .keep)
    }

    func testWritesWhileUnknownOnlyMoveTheWindow() {
        var w = FieldWatch(start: "x")
        w.forget()
        w.wrote(deleting: 0, inserting: "abc", at: 3)
        XCTAssertEqual(w.lastOwnEdit, 3)
        XCTAssertEqual(w.history, [""])
        w.wrote(deleting: 0, inserting: "", at: 4)  // nothing written: the window does not move
        XCTAssertEqual(w.lastOwnEdit, 3)
    }

    func testTheModelStaysBounded() {
        var w = FieldWatch(start: "")
        for i in 0..<300 {
            w.wrote(deleting: 0, inserting: "단어\(i) ", at: Double(i))
            w.begin(O(before: w.expected))
        }
        XCTAssertLessThanOrEqual(w.start.count, FieldWatch.keptStart)
        for i in 0..<200 { w.wrote(deleting: 2, inserting: "", at: Double(300 + i)) }
        XCTAssertLessThanOrEqual(w.lead.count, FieldWatch.keptLead)
    }
}
