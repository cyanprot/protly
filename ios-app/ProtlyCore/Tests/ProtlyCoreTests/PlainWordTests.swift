import XCTest
@testable import ProtlyCore

/// A text field as the keyboard sees it: deleteBackward removes one Character, insertText appends.
struct FakeField {
    private(set) var text: String
    /// The fewest Characters the field held at any moment: no edit may reach the text before the word.
    private(set) var lowest: Int
    /// The text before the latest call: what a context one state late shows.
    private(set) var previous: String?

    init(_ text: String) {
        self.text = text
        lowest = text.count
    }

    mutating func deleteBackward() {
        guard !text.isEmpty else {
            XCTFail("deleteBackward on an empty field: an edit deleted more than the field holds")
            return
        }
        previous = text
        text.removeLast()
        lowest = min(lowest, text.count)
    }

    mutating func insertText(_ s: String) {
        previous = text
        text += s
    }

    /// One edit starts: a new low-water mark, and no call made yet.
    mutating func beginEdit() {
        lowest = text.count
        previous = nil
    }
}

/// The keyboard's write path (KeyboardViewController.apply) over a FakeField, checked after every edit, with
/// FieldWatch driven alongside as the keyboard drives it: begin at a word's first key, the check before a write
/// over the word, wrote after each write. One op every 100 ms.
struct Replay {
    typealias O = FieldWatch.Observed
    var session: TypingSession
    var field: FakeField
    var written = ""
    var watch = FieldWatch(known: false)
    var t = 0.0
    /// The field text before the word being typed (or before the word just committed).
    var wordStart: String
    var calls = 0  // proxy calls, for the record

    init(_ session: TypingSession, field: String = "오늘 ") {
        self.session = session
        self.field = FakeField(field)
        wordStart = field
    }

    enum Op { case key(Character), shifted(Character), backspace, flip, commit, accept, space }

    mutating func run(_ ops: [Op], file: StaticString = #filePath, line: UInt = #line) {
        for op in ops { run(op, file: file, line: line) }
    }

    mutating func run(_ op: Op, file: StaticString = #filePath, line: UInt = #line) {
        t += 0.1
        switch op {
        case .key, .shifted:
            if !session.isComposing {  // the word's first key
                wordStart = field.text
                watch.begin(O(before: field.text), now: t)
                XCTAssertEqual(watch.expected, field.text, "model at the first key", file: file, line: line)
            }
        default: break
        }
        let edit: FieldEdit?
        switch op {
        case .key(let c): edit = session.type(KeyEvent(c))
        case .shifted(let c): edit = session.type(KeyEvent(c, .manual))
        case .backspace: edit = session.backspace()
        case .flip: edit = session.flip()
        case .commit: edit = session.commit()
        case .accept: edit = session.accept()
        case .space:
            edit = session.commit()
            if let edit { apply(edit, file: file, line: line) }
            field.beginEdit()
            field.insertText(" ")
            calls += 1
            watch.wrote(deleting: 0, inserting: " ", at: t)
            session.noteInserted(" ")
            checkWatch(file: file, line: line)
            return
        }
        if let edit { apply(edit, file: file, line: line) }
    }

    private mutating func apply(_ edit: FieldEdit, file: StaticString, line: UInt) {
        let before = written
        field.beginEdit()
        let step = PlainWord.step(edit, written: written)
        if !before.isEmpty, step.deleting > 0 || !step.inserting.isEmpty {
            // The keyboard's check before a write over the word.
            XCTAssertEqual(watch.decide(O(before: field.text), composing: true, lastTail: nil, now: t), .keep,
                           "before \(edit)", file: file, line: line)
        }
        for _ in 0..<step.deleting { field.deleteBackward() }
        if !step.inserting.isEmpty { field.insertText(step.inserting) }
        calls += step.deleting + (step.inserting.isEmpty ? 0 : 1)
        watch.wrote(deleting: step.deleting, inserting: step.inserting, at: t)
        written = step.written
        checkWatch(file: file, line: line)
        switch edit {
        case .mark(let text):
            XCTAssertEqual(field.text, wordStart + text, "after \(edit)", file: file, line: line)
            XCTAssertEqual(written, text, file: file, line: line)
            XCTAssertLessThanOrEqual(step.deleting, before.count, "\(edit) deletes past the word", file: file, line: line)
            XCTAssertGreaterThanOrEqual(field.lowest, wordStart.count, "\(edit) reached before the word", file: file, line: line)
        case .commit(let text):
            XCTAssertEqual(field.text, wordStart + text, "after \(edit)", file: file, line: line)
            XCTAssertEqual(written, "", file: file, line: line)
            XCTAssertLessThanOrEqual(step.deleting, before.count, "\(edit) deletes past the word", file: file, line: line)
            XCTAssertGreaterThanOrEqual(field.lowest, wordStart.count, "\(edit) reached before the word", file: file, line: line)
        case .replace(_, let text):
            // A flip of the committed word: the word and the spaces after it, nothing before the word.
            XCTAssertEqual(field.text, wordStart + text, "after \(edit)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(field.lowest, wordStart.count, "\(edit) reached before the word", file: file, line: line)
        }
    }

    /// FieldWatch's model is the field, and a host callback now keeps the word, whether it reads the field as it is
    /// or one state late.
    private func checkWatch(file: StaticString, line: UInt) {
        // The keyboard opens with an unknown model; a space or commit before any key leaves it unknown.
        guard watch.known else { return }
        XCTAssertEqual(watch.expected, field.text, "model", file: file, line: line)
        let now = t + 0.01
        if session.isComposing {
            XCTAssertEqual(watch.decide(O(before: field.text), composing: true, lastTail: nil, now: now), .keep,
                           "true read of \(field.text)", file: file, line: line)
            if let previous = field.previous {
                XCTAssertEqual(watch.decide(O(before: previous), composing: true, lastTail: nil, now: now), .keep,
                               "late read of \(field.text): \(previous)", file: file, line: line)
            }
        } else if let tail = session.lastTail {
            XCTAssertEqual(watch.decide(O(before: field.text), composing: false, lastTail: tail, now: now), .keep,
                           "flip check", file: file, line: line)
        }
    }
}

final class PlainWordTests: XCTestCase {
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 1000), ("hi", 800), ("go", 500)]),
        korean: WordList(entries: [("go", 500), ("dkssud", 50)]),  // 해, 안녕
        priorBonus: 2.0
    )
    let suggestions = LanguageDetector(
        english: WordList(entries: [("the", 50_000), ("there", 30_000)]),
        korean: WordList(entries: [("dkssud", 500), ("dkssudgktpdy", 300)]),  // 안녕 안녕하세요
        priorBonus: 2.0
    )

    private func check(_ old: String, _ new: String, _ deleting: Int, _ inserting: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let e = PlainWord.edit(from: old, to: new)
        XCTAssertEqual(e.deleting, deleting, "\(old) -> \(new)", file: file, line: line)
        XCTAssertEqual(e.inserting, inserting, "\(old) -> \(new)", file: file, line: line)
    }

    private func keys(_ s: String) -> [Replay.Op] { s.map { Replay.Op.key($0) } }

    // MARK: edit

    func testTheSixCasesFromTheResearch() {
        check("", "ㅇ", 0, "ㅇ")
        check("안녕핫", "안녕하세", 1, "하세")
        check("ㅗㄷ", "hel", 2, "hel")
        check("안", "", 1, "")
        check("안녕", "안녕", 0, "")
        check("ㅋㅋ", "ㅋㅋㅋ", 0, "ㅋ")
    }

    func testCountsAreCharactersNotScalarsOrUTF16() {
        check("e\u{301}", "e", 1, "e")         // é as e + combining acute is one Character
        check("😀a", "😀b", 1, "b")            // the emoji is two UTF-16 units, one Character
        check("가", "각", 1, "각")             // a precomposed syllable is replaced whole
    }

    func testStepKeepsTheWordUntilCommitAndReplaceLeavesItAlone() {
        XCTAssertEqual(PlainWord.step(.mark("안"), written: "아"),
                       PlainWord.Step(deleting: 1, inserting: "안", written: "안"))
        XCTAssertEqual(PlainWord.step(.commit("안녕"), written: "안녕"),
                       PlainWord.Step(deleting: 0, inserting: "", written: ""))
        XCTAssertEqual(PlainWord.step(.commit("안녕"), written: "dkssud"),
                       PlainWord.Step(deleting: 6, inserting: "안녕", written: ""))
        XCTAssertEqual(PlainWord.step(.mark(""), written: "ㄱ"),
                       PlainWord.Step(deleting: 1, inserting: "", written: ""))
        XCTAssertEqual(PlainWord.step(.replace(deleting: 3, inserting: "dkssud "), written: ""),
                       PlainWord.Step(deleting: 3, inserting: "dkssud ", written: ""))
    }

    // MARK: replay: the field holds the word after every key

    func testAnnyeonghaseyoKeyByKey() {
        var r = Replay(TypingSession(detector: suggestions, previous: .korean))
        r.run(keys("dkssudgktpdy"))
        XCTAssertEqual(r.field.text, "오늘 안녕하세요")
        r.run(.commit)
        XCTAssertEqual(r.field.text, "오늘 안녕하세요")
        XCTAssertEqual(r.written, "")
    }

    func testHelloAfterKorean() {
        var r = Replay(TypingSession(detector: detector, previous: .korean), field: "안녕 ")
        r.run(keys("hello"))
        r.run(.commit)
        XCTAssertEqual(r.field.text, "안녕 hello")
    }

    func testBackspaceInsideAnnyeong() {
        var r = Replay(TypingSession(detector: detector))
        r.run(keys("dkssud"))
        XCTAssertEqual(r.field.text, "오늘 안녕")
        r.run(.backspace)
        XCTAssertEqual(r.field.text, "오늘 안녀")
        r.run([.backspace, .key("u"), .key("d")])
        XCTAssertEqual(r.field.text, "오늘 안녕")
        r.run([Replay.Op](repeating: .backspace, count: 6))
        XCTAssertEqual(r.field.text, "오늘 ")
        XCTAssertEqual(r.written, "")
        XCTAssertFalse(r.session.isComposing)
        XCTAssertNil(r.session.backspace())  // the keyboard deletes normally from here
    }

    func testBackspaceThroughASyllable() {
        var r = Replay(TypingSession(detector: detector))
        r.run(keys("rkr"))
        XCTAssertEqual(r.field.text, "오늘 각")
        r.run([.backspace, .backspace, .backspace])  // 가, ㄱ, ""
        XCTAssertEqual(r.field.text, "오늘 ")
    }

    func testFlipWhileTyping() {
        var r = Replay(TypingSession(detector: detector))
        r.run(keys("dkssud"))
        r.run(.flip)
        XCTAssertEqual(r.field.text, "오늘 dkssud")
        r.run([.key("s"), .commit])
        XCTAssertEqual(r.field.text, "오늘 dkssuds")
    }

    func testFlipOfTheCommittedWordOverItsSpace() {
        var r = Replay(TypingSession(detector: detector))
        r.run(keys("dkssud"))
        r.run(.space)
        XCTAssertEqual(r.field.text, "오늘 안녕 ")
        r.run(.flip)
        XCTAssertEqual(r.field.text, "오늘 dkssud ")
        r.run(.flip)
        XCTAssertEqual(r.field.text, "오늘 안녕 ")
    }

    func testCommitRewritesTheWordWhenItsReadingChanges() {
        // Without the word lists, Hangul after an English word shows Latin while typing and commits Korean.
        var r = Replay(TypingSession(detector: nil, previous: .english), field: "hello ")
        r.run(keys("dkssud"))
        XCTAssertEqual(r.field.text, "hello dkssud")
        r.run(.commit)
        XCTAssertEqual(r.field.text, "hello 안녕")
    }

    func testAcceptASuggestion() {
        var r = Replay(TypingSession(detector: suggestions, previous: .korean))
        r.run(keys("dkssudg"))  // 안녕ㅎ
        XCTAssertEqual(r.session.suggestion, "안녕하세요")
        r.run(.accept)
        XCTAssertEqual(r.field.text, "오늘 안녕하세요")
        XCTAssertEqual(r.written, "")
    }

    func testAcceptATypoFixRewritesInsideTheWord() {
        var r = Replay(TypingSession(detector: suggestions, previous: .english), field: "hi ")
        r.run(keys("teh"))
        XCTAssertEqual(r.session.suggestion, "the")
        r.run(.accept)
        XCTAssertEqual(r.field.text, "hi the")
    }

    func testAcceptAfterAFlip() {
        let d = LanguageDetector(
            english: WordList(entries: [("go", 900), ("good", 500)]),
            korean: WordList(entries: [("gody", 400)]),  // 해요
            priorBonus: 2.0
        )
        var r = Replay(TypingSession(detector: d, previous: .english), field: "")
        r.run(keys("go"))
        XCTAssertEqual(r.field.text, "go")
        r.run(.flip)
        XCTAssertEqual(r.field.text, "해")
        r.run(.accept)
        XCTAssertEqual(r.field.text, "해요")
    }

    func testManualShiftAndAWordInAnEmptyField() {
        var r = Replay(TypingSession(detector: detector), field: "")
        r.run([.shifted("q"), .key("k"), .key("d")])  // 빵
        XCTAssertEqual(r.field.text, "빵")
        r.run(.space)
        r.run(keys("the"))
        r.run(.commit)
        XCTAssertEqual(r.field.text, "빵 the")
    }

    func testEachKeyIsAboutTwoProxyCalls() {
        // marked-text-dark.md section 5: 21 proxy calls for the 12 keys of 안녕하세요.
        var r = Replay(TypingSession(detector: suggestions, previous: .korean))
        r.run(keys("dkssudgktpdy"))
        XCTAssertEqual(r.calls, 21)
    }

    /// Random keys, backspaces, flips, commits and spaces from a fixed seed: the field always holds the word.
    func testRandomSequencesKeepTheFieldEqualToTheWord() {
        var rng = SplitMix64(seed: 0x5EED)
        let letters = Array("dkssudgktpdyrhelowqmfzn")
        for _ in 0..<200 {
            var r = Replay(TypingSession(detector: detector, previous: rng.next() % 2 == 0 ? Language.korean : Language.english))
            for _ in 0..<30 {
                switch rng.next() % 10 {
                case 0, 1: r.run(.backspace)
                case 2: r.run(.flip)
                case 3: r.run(.space)
                case 4: r.run(.commit)
                default: r.run(.key(letters[Int(rng.next() % UInt64(letters.count))]))
                }
            }
            r.run(.commit)
            XCTAssertEqual(r.written, "")
            XCTAssertTrue(r.field.text.hasPrefix("오늘 "), r.field.text)
        }
    }

    // MARK: the session side of a key that finds the field moved

    func testAKeyThatFindsTheFieldMovedStartsAFreshWordWithThatKey() {
        // The keyboard has already handed the key to the session when FieldWatch abandons the word: abandon,
        // then type the key again into the fresh word. Nothing is deleted; the key is not lost.
        var s = TypingSession(detector: detector, previous: .korean)
        var written = ""
        for c in "dkssud" { written = PlainWord.step(s.type(KeyEvent(c)), written: written).written }
        XCTAssertEqual(written, "안녕")
        _ = s.type(KeyEvent("g"))  // taken, but the field moved: not written
        s.abandon()
        written = ""
        XCTAssertFalse(s.isComposing)
        XCTAssertEqual(s.previous, .korean)
        let step = PlainWord.step(s.type(KeyEvent("g")), written: written)
        XCTAssertEqual(step, PlainWord.Step(deleting: 0, inserting: "ㅎ", written: "ㅎ"))
        XCTAssertEqual(s.keys.count, 1)
    }

    func testABackspaceThatFindsTheFieldMovedLeavesTheDeleteToTheKeyboard() {
        var s = TypingSession(detector: detector)
        for c in "dkssud" { _ = s.type(KeyEvent(c)) }
        _ = s.backspace()  // taken, but the field moved: not written
        s.abandon()
        XCTAssertFalse(s.isComposing)
        XCTAssertNil(s.backspace())  // the next backspace is KeyboardKit's
    }
}

/// A fixed-seed generator so a failing random sequence can be replayed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
