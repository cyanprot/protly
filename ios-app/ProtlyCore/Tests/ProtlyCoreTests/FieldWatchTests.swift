import XCTest
@testable import ProtlyCore

final class FieldWatchTests: XCTestCase {
    typealias O = FieldWatch.Observed
    let window = FieldWatch.ownEditWindow
    let lag = FieldWatch.lagWindow
    let lateEnough = 10.0  // well past both windows

    /// A word 안녕 typed key by key after "오늘 ", every write at t = 0.
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

    func testANoBreakSpaceCountsAsASpace() {
        // WebKit contenteditable reports "hello " as "hello\u{00A0}" until the next character.
        XCTAssertEqual(decide(typed(["w"], start: "hello\u{00A0}"), O(before: "hello w")), .keep)
        XCTAssertEqual(decide(typed(["w"], start: "hello "), O(before: "hello\u{00A0}w")), .keep)
        XCTAssertEqual(decide(typed(["w"], after: " x"), O(before: "오늘 w", after: "\u{00A0}x")), .keep)
    }

    // MARK: a context that lags behind Protly's writes

    func testAContextShowingAnEarlierStateKeepsOnlyWhileItLags() {
        let w = typed(["안", "안ㄴ", "안녀"])
        XCTAssertEqual(decide(w, O(before: "오늘 안ㄴ"), at: lag / 2), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 안"), at: lag / 2), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 "), at: lag / 2), .keep)  // before the first key
        // Older than the lag window: the host undid or refused the text. Abandon, even inside the own-edit window.
        XCTAssertEqual(decide(w, O(before: "오늘 안ㄴ"), at: lag * 1.5), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘 "), at: lag * 1.5), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘 "), at: lateEnough), .abandon)  // a host undo of the whole word
    }

    func testAFieldThatDropsTheInsertDoesNotLoseTheUsersText() {
        // A full capped field ending "xyz": d is dropped (the field still shows "xyz"), then k would make ㅇ into 아
        // with one delete, which would take the z.
        var w = FieldWatch()
        w.begin(O(before: "xyz"), now: 0)
        XCTAssertEqual(w.start, "xyz")
        w.wrote(deleting: 0, inserting: "ㅇ", at: 1)
        XCTAssertEqual(PlainWord.edit(from: "ㅇ", to: "아").deleting, 1)
        XCTAssertEqual(decide(w, O(before: "xyz"), at: 1 + lag + 0.05), .abandon)
        XCTAssertEqual(decide(w, O(before: "xyz"), at: 1 + window / 2 + 0.01), .abandon)  // the own-edit window does not help
        // Faster than the lag window the read cannot be told from a lagging one.
        XCTAssertEqual(decide(w, O(before: "xyz"), at: 1 + lag / 2), .keep)
    }

    func testTheStatesBetweenTheDeletesAndTheInsertAreInTheHistory() {
        // ㄱ to 가 deletes ㄱ, then inserts 가: a context read between the two shows the empty word.
        var w = FieldWatch(start: "오늘 ")
        w.wrote(deleting: 0, inserting: "ㄱ", at: 0)
        w.wrote(deleting: 1, inserting: "가", at: 0.05)
        XCTAssertEqual(w.history, ["", "ㄱ", "", "가"])
        XCTAssertEqual(w.expected, "오늘 가")
        XCTAssertEqual(decide(w, O(before: "오늘 "), at: 0.1), .keep)
        XCTAssertEqual(decide(w, O(before: "오늘 ㄱ"), at: 0.1), .keep)
    }

    func testAFirstKeyThatReadsAContextMissingProtlysSpaceKeeps() {
        // "hello" was typed, Protly inserted " ", and the next word's first key read the stale "hello".
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "hello", at: 0)
        w.wrote(deleting: 0, inserting: " ", at: 0.1)
        var late = w
        w.begin(O(before: "hello"), now: 0.15)
        XCTAssertEqual(w.start, "hello ")  // Protly's model, not the stale read
        w.wrote(deleting: 0, inserting: "ㅇ", at: 0.2)
        XCTAssertEqual(decide(w, O(before: "hello"), at: 0.22), .keep)       // still stale
        XCTAssertEqual(decide(w, O(before: "hello "), at: 0.22), .keep)      // caught up with the space
        XCTAssertEqual(decide(w, O(before: "hello ㅇ")), .keep)              // caught up
        XCTAssertEqual(decide(w, O(before: "hello"), at: 0.4), .abandon)     // too old to be lag
        XCTAssertEqual(decide(w, O(before: "helloㅇ")), .abandon)            // not a state Protly wrote
        // The same read long after the space is not lag: the word starts at the context.
        late.begin(O(before: "hello"), now: 2)
        XCTAssertEqual(late.start, "hello")
    }

    func testAnEmptyContextKeepsOnlyInsideTheWindow() {
        let w = typed()
        XCTAssertEqual(decide(w, O(before: ""), at: window / 2), .keep)
        XCTAssertEqual(decide(w, O(before: ""), at: window * 2), .abandon)
        XCTAssertEqual(decide(w, O(before: "오늘"), at: window / 2), .keep)  // matches nothing: the model is trusted
    }

    func testTheWindowStartsAtTheLastWrite() {
        var w = typed()
        w.wrote(deleting: 0, inserting: "ㅎ", at: 5)
        XCTAssertEqual(decide(w, O(before: ""), at: 5 + window / 2), .keep)
        XCTAssertEqual(decide(w, O(before: ""), at: 5 + window + 0.001), .abandon)
        XCTAssertEqual(decide(w, O(before: ""), at: 4), .abandon)  // a clock before the write is not in the window
    }

    func testNothingIsInTheWindowBeforeTheFirstWrite() {
        let w = FieldWatch(start: "오늘 ", history: ["", "안"], lastOwnEdit: nil)
        XCTAssertEqual(w.decide(O(before: "다른"), composing: true, lastTail: nil, now: 0), .abandon)
    }

    /// A web view that reports each context 100 ms late, with a key every 120 ms: Protly's own typing is never
    /// abandoned. Then the host sends the message and clears the field: abandon.
    func testALaggingHostNeverAbandonsOwnTyping() {
        let words: [(marks: [String], commit: String)] = [
            (["ㅇ", "아", "안", "안ㄴ", "안녀", "안녕"], "안녕"),
            (["ㅗ", "ㅗㄷ", "hel", "hell", "hello"], "hello"),
            (["d", "dk", "dks", "dkss", "dkssu", "dkssud"], "안녕"),  // Latin while typing, Korean at the commit
        ]
        var field: [(text: String, at: Double)] = [("오늘 ", -1)]  // every state the field passes through
        func read(at now: Double) -> O {
            O(before: field.last { $0.at <= now - 0.1 }?.text ?? field[0].text)
        }
        func write(_ e: (deleting: Int, inserting: String), at t: Double) {
            for _ in 0..<e.deleting { field.append((String(field[field.count - 1].text.dropLast()), t)) }
            if !e.inserting.isEmpty { field.append((field[field.count - 1].text + e.inserting, t)) }
        }
        var w = FieldWatch(known: false)
        var t = 0.0
        for word in words {
            t += 0.12
            w.begin(read(at: t), now: t)
            var written = ""
            for (k, text) in word.marks.enumerated() {
                if k > 0 { t += 0.12 }
                let e = PlainWord.edit(from: written, to: text)
                write(e, at: t)
                w.wrote(deleting: e.deleting, inserting: e.inserting, at: t)
                written = text
                for dt in [0.0, 0.05, 0.11] {
                    XCTAssertEqual(w.decide(read(at: t + dt), composing: true, lastTail: nil, now: t + dt), .keep,
                                   "\(text) at +\(dt)")
                }
            }
            t += 0.12
            let e = PlainWord.edit(from: written, to: word.commit)
            write(e, at: t)
            w.wrote(deleting: e.deleting, inserting: e.inserting, at: t)
            write((0, " "), at: t)
            w.wrote(deleting: 0, inserting: " ", at: t)
        }
        XCTAssertEqual(field.last?.text, "오늘 안녕 hello 안녕 ")
        XCTAssertEqual(w.expected, "오늘 안녕 hello 안녕 ")
        XCTAssertEqual(w.decide(O(before: ""), composing: true, lastTail: nil, now: t + 1), .abandon)
    }

    // MARK: a context cut at the front

    func testALongFieldCutAtTheFrontKeeps() {
        let start = String(String(repeating: "가나다라마 ", count: 84).prefix(500))
        XCTAssertEqual(start.count, 500)
        let w = typed(start: start)
        XCTAssertEqual(decide(w, O(before: String((start + "안녕").suffix(100)))), .keep)
        XCTAssertEqual(decide(w, O(before: String((start + "안ㄴ").suffix(100))), at: lag / 2), .keep)  // and lagging
        XCTAssertEqual(decide(w, O(before: String((start + "안녕ㅎ").suffix(100)))), .abandon)
    }

    func testAContextLongerThanTheModelStillMatches() {
        // The model came from a cut context; a later read shows more of the field.
        let w = typed(start: "늘 ")
        XCTAssertEqual(decide(w, O(before: "어제 오늘 안녕")), .keep)
    }

    func testAContextCutToTheWordAloneKeeps() {
        // Some hosts report only the current sentence, or less: the end of the model still agrees.
        XCTAssertEqual(decide(typed(), O(before: "녕")), .keep)
    }

    // MARK: no word being typed

    func testWithNoWordOnlyTheFlipIsChecked() {
        let w = FieldWatch(start: "오늘 ")
        XCTAssertEqual(w.decide(O(before: "오늘 안녕 "), composing: false, lastTail: "안녕 ", now: 0), .keep)
        XCTAssertEqual(w.decide(O(before: "오늘 안녕"), composing: false, lastTail: "안녕 ", now: 0), .forgetLast)
        XCTAssertEqual(w.decide(O(before: ""), composing: false, lastTail: nil, now: 0), .keep)
        XCTAssertEqual(w.decide(O(before: "x", selected: "x"), composing: false, lastTail: nil, now: 0), .keep)
    }

    func testASelectionEndsTheFlip() {
        // "오늘 |world": hello and a space typed, then a double-tap on world. A flip would delete the selection and
        // part of the word ("오늘 hㅗ디ㅣㅐ ").
        let w = FieldWatch(start: "오늘 ")
        XCTAssertEqual(w.decide(O(before: "오늘 hello ", selected: "world"), composing: false,
                                lastTail: "hello ", now: 0), .forgetLast)
    }

    // MARK: the model

    func testBeginTakesTheContextWhenTheModelIsUnknownOrTheCursorMoved() {
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "hello ", at: 0)
        var moved = w
        moved.begin(O(before: "hel", after: "lo "), now: 0.05)  // tapped inside "hello"
        XCTAssertEqual(moved.start, "hel")
        XCTAssertEqual(moved.after, "lo ")
        var selected = w
        selected.begin(O(before: "", selected: "hello "), now: 0.05)
        XCTAssertEqual(selected.start, "")
        var forgotten = w
        forgotten.forget()
        XCTAssertFalse(forgotten.known)
        forgotten.begin(O(before: "hello"), now: 0.05)
        XCTAssertEqual(forgotten.start, "hello")
        XCTAssertTrue(forgotten.known)
        var other = w
        other.begin(O(before: "something else"), now: 0.05)
        XCTAssertEqual(other.start, "something else")
        XCTAssertEqual(other.lead, [])
    }

    func testBeginNeverTakesAnEmptyContextForLag() {
        // A chat app sent "안녕\n" and cleared the field: the next word starts in an empty field.
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: "안녕", at: 0)
        w.wrote(deleting: 0, inserting: "\n", at: 0.1)
        w.begin(O(before: ""), now: 0.12)
        XCTAssertEqual(w.start, "")
        XCTAssertEqual(w.lead, [])
    }

    func testBeginKeepsTheLongerOfAMatchingContextAndModel() {
        var w = FieldWatch(start: "늘 ")
        w.wrote(deleting: 0, inserting: "안녕 ", at: 0)
        w.begin(O(before: "어제 오늘 안녕 "), now: 5)
        XCTAssertEqual(w.start, "어제 오늘 안녕 ")
        XCTAssertEqual(w.history, [""])
    }

    func testBeginKeepsTheModelWhenTheContextIsCutAtTheFront() {
        let long = String(repeating: "가나다라마 ", count: 100)  // 600 Characters
        var w = FieldWatch(start: "")
        w.wrote(deleting: 0, inserting: long, at: 0)
        w.begin(O(before: String(long.suffix(100))), now: 5)
        XCTAssertEqual(w.start, long)
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
        w.begin(O(before: "오늘 안"), now: 0.35)  // stale: shows the field after the first of the three deletes
        XCTAssertEqual(w.start, "오늘")
        w.wrote(deleting: 0, inserting: "ㅇ", at: 0.4)
        XCTAssertEqual(decide(w, O(before: "오늘 안"), at: 0.42), .keep)
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
            w.begin(O(before: w.expected), now: Double(i))
        }
        XCTAssertLessThanOrEqual(w.start.count, FieldWatch.keptStart)
        for i in 0..<200 { w.wrote(deleting: 2, inserting: "", at: Double(300 + i)) }
        XCTAssertLessThanOrEqual(w.lead.count, FieldWatch.keptLead)
        // A long run of writes with no new word (digits typed one by one): the newest states stay.
        var digits = FieldWatch(start: "")
        var typedDigits = ""
        for i in 0..<500 {
            digits.wrote(deleting: 0, inserting: String(i % 10), at: Double(i))
            typedDigits += String(i % 10)
        }
        XCTAssertLessThanOrEqual(digits.history.count, FieldWatch.keptHistory)
        XCTAssertLessThanOrEqual(digits.lead.count, FieldWatch.keptLead)
        XCTAssertEqual(digits.expected, typedDigits)
        let previous = O(before: String(typedDigits.dropLast()))  // ends in 8, the model in 9: an earlier state
        XCTAssertEqual(digits.decide(previous, composing: true, lastTail: nil, now: 499.05), .keep)
        XCTAssertEqual(digits.decide(previous, composing: true, lastTail: nil, now: 499.2), .abandon)
    }
}
