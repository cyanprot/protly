# protly iOS keyboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use execute-flow to implement this plan task-by-task.

**Goal:** Turn protly into a custom iPhone keyboard that looks like Apple's, switches Korean/English per word on its
own, and puts Translate/Polish/read in the predictive bar and a same-height panel.

**Architecture:** `ios-app/` holds two SwiftPM packages. `ios-app/ProtlyCore/` is platform-free logic (Hangul
composer, language detector, word lists), tested on Linux with `swift test`. `ios-app/` itself is the xtool app
package: a container app `Protly` and a keyboard extension `ProtlyKeyboard` built on a vendored, patched
KeyboardKit 9.9.1. Built and installed on Fedora with xtool and a free Apple ID; no Mac.

**Tech Stack:** Swift 6.4.1 (swift.org Fedora 41 build via swiftly), xtool 1.24.0, Xcode 27.1 SDK (from the .xip),
KeyboardKit 9.9.1 (MIT, vendored), XCTest, FrequencyWords 2018 word lists (CC-BY-SA-4.0), Tatoeba sentences
(CC-BY 2.0 FR).

**Design:** `docs/plans/2026-10-28-ios-keyboard-design.md` (approved, spec-reviewed, commit e3db8e6). Read it first,
then the amendments below, which override it.

---

## Scope of this plan

Sprints 1 and 2 are written in full. Sprints 3-6 depend on what the Sprint 2 phone spike finds (whether xtool keeps
the extension's code, how KeyboardKit renders, marked text, clipboard prompt, context length), so they are given as
sprint contracts only. After the Sprint 2 gate passes, run `/plan-flow` again on Sprints 3-6 with
`docs/ios-keyboard-notes.md` as input. Writing their code now would be guessing.

## Design amendments (research done while planning, 2026-10-28)

1. **No App Group.** xtool silently drops the App Groups entitlement on free Apple ID teams
   (`DeveloperServicesCapability(.appGroups, isFree: false)` in xtool 1.24.0). The app and the keyboard therefore
   share nothing at runtime. Consequences:
   - The phone's API key is baked into the keyboard at build time from `~/.config/protly/phone-api-key` (one line,
     chmod 600, never printed) into the gitignored `ios-app/Sources/ProtlyKeyboard/Secrets.swift`. This is the
     same exposure as today's Shortcut, whose Text action holds the key.
   - The workspace ID is not secret (it is already in `ios/protly.cherri:89`): it is a constant in code.
   - Learned words live in the keyboard's own container.
   - The container app is a setup guide plus a test text field. Nothing to enter there.
   - If the user moves to the paid program later, App Groups come back and settings can move into the app.
2. **Toolchain.** xtool 1.24.0 needs Swift 6.4 and the Xcode 27.1 SDK. Fedora's `swift-lang` is 6.3.2, too old.
   The swift.org 6.4.1 build exists only for `fedora41`; swiftly installs it with `--platform fedora41`. The
   `swift-lang` package installed during planning is removed in Task 1.1.
3. **xtool rewrites bundle IDs** at signing time to `XTL-<team>.com.northprot.protly`. Code never hard-codes the
   bundle ID.
4. **Known xtool risks** (open issues at 1.24.0): extension code dead-stripped at link time (#313, #379), and no
   `actool` for `.xcassets` (#123 wontfix). Sprint 2 tests a bare keyboard first, then KeyboardKit with its two
   asset-catalog files patched to colors in code.
5. **Language detector rules** were measured during planning (Task 1.6 reproduces the numbers): a word that is
   one jamo repeated (ㅋㅋ ㅇㅇ ㄱㄱ ㅠㅠ) is Korean; while typing, when both languages still fit, the previous
   word's language is kept, Korean at the start of a message. Prior bonus 2.0.

## Ground rules for every task

- Repo is local only. Never `git push`. Commit trailer, exactly:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011iEAzV8i2g4RP4No1hQ6es
  ```
- Never print, cat, echo or log the API key, `~/.config/protly/phone-api-key`, `~/.config/anthropic/api-key`,
  or `ios-app/Sources/ProtlyKeyboard/Secrets.swift`. Check that the file exists with `test -s`, nothing more.
- Before every commit: `npm test` (existing extension and iOS template tests; must stay `# fail 0` and Python
  `OK`) and, once `ios-app/ProtlyCore` exists, `swift test --package-path ios-app/ProtlyCore`.
- Claude cannot touch the phone. Steps marked **USER** are done by the user; Claude prints the exact steps and
  waits. Interactive logins (Apple ID, 2FA) are run by the user with the `!` prefix.
- All UI strings in the app and keyboard are English.
- Downloads go to the session scratchpad first, never executed from there except the pinned toolchain installers
  named in this plan.

## Files added by Sprints 1-2

```
ios-app/
  ProtlyCore/
    Package.swift
    ATTRIBUTION.md
    Sources/ProtlyCore/{Keys,Hangul,KeyEncoder,WordList,LanguageDetector}.swift
    Sources/ProtlyCore/Resources/{en_50k,ko_50k}.txt
    Sources/protly-eval/main.swift
    Tests/ProtlyCoreTests/{Hangul,KeyEncoder,LanguageDetector}Tests.swift
    Corpus/{chat,tatoeba-kor,tatoeba-eng}.txt
    scripts/make-corpus.sh
  Package.swift
  xtool.yml
  Support/ProtlyKeyboard-Info.plist
  Sources/Protly/ProtlyApp.swift
  Sources/ProtlyKeyboard/{KeyboardViewController,Spike}.swift
  Sources/ProtlyKeyboard/Secrets.swift        (gitignored, generated)
  scripts/make-secrets.sh
  Vendor/KeyboardKit/                          (Task 2.6)
docs/ios-keyboard-notes.md
```

---

# Sprint 1: ProtlyCore on Linux

Delivers the composer and detector with measured accuracy. No phone. After Task 1.1, Tasks 1.2-1.6 and Sprint 2
Tasks 2.1-2.2 can run in parallel (separate folders; both need the 6.4.1 toolchain).

### Task 1.1: Swift 6.4.1 toolchain

**Step 1: Install swiftly and Swift 6.4.1 (Fedora 41 build)**

Run in the scratchpad directory:
```bash
cd "$SCRATCH" && curl -fLO https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init --platform fedora41 --quiet-shell-followup --assume-yes
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && hash -r
swiftly install 6.4.1 && swiftly use 6.4.1
```
`--platform fedora41` is required: swiftly does not know Fedora 44. If `init` already installed a newer 6.4.x as
default, keep 6.4.1 pinned anyway (the Xcode 27.1 SDK pairs with 6.4).

**Step 2: Remove the Fedora 6.3.2 package so it cannot shadow swiftly on PATH**

```bash
sudo dnf remove -y swift-lang swift-lang-runtime
hash -r; command -v swift; swift --version
```
Expected: the path is under `~/.local/share/swiftly/bin/`, version `Swift version 6.4.1`.

**Step 3: Make it permanent for new shells**

Check that swiftly's init added `. ~/.local/share/swiftly/env.sh` to `~/.bashrc` (`grep -n swiftly ~/.bashrc`).
If not, append that one line. Open a new shell (`bash -lc 'swift --version'`) and confirm 6.4.1.

Nothing to commit.

### Task 1.2: Package skeleton and word lists

**Files:**
- Create: `ios-app/ProtlyCore/Package.swift`
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/Resources/en_50k.txt`, `ko_50k.txt`
- Create: `ios-app/ProtlyCore/ATTRIBUTION.md`
- Modify: `.gitignore`

**Step 1: Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

// ProtlyCore: platform-free keyboard logic (no UIKit). Builds and tests on Linux.
let package = Package(
    name: "ProtlyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProtlyCore", targets: ["ProtlyCore"]),
    ],
    targets: [
        .target(
            name: "ProtlyCore",
            resources: [.copy("Resources/en_50k.txt"), .copy("Resources/ko_50k.txt")]
        ),
        .executableTarget(name: "protly-eval", dependencies: ["ProtlyCore"]),
        .testTarget(name: "ProtlyCoreTests", dependencies: ["ProtlyCore"]),
    ]
)
```

**Step 2: Word lists**

```bash
cd ~/projects/protly/ios-app/ProtlyCore/Sources/ProtlyCore/Resources
for l in en ko; do curl -fL -o ${l}_50k.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/$l/${l}_50k.txt; done
wc -l en_50k.txt ko_50k.txt   # expect 50000 each; first lines "you 28787591" and "내가 39801"
```

**Step 3: ATTRIBUTION.md**

```markdown
# Data attribution

- `Sources/ProtlyCore/Resources/en_50k.txt`, `ko_50k.txt`: FrequencyWords by Hermit Dave
  (https://github.com/hermitdave/FrequencyWords), 2018 lists from OpenSubtitles, CC-BY-SA-4.0.
- `Corpus/tatoeba-*.txt`: sentences from Tatoeba (https://tatoeba.org), CC-BY 2.0 FR. Sampled by
  `scripts/make-corpus.sh`.
- `Corpus/chat.txt`: written for this project.
```

**Step 4: .gitignore**

Append:
```
.build/
ios-app/xtool/
ios-app/.swiftpm/
ios-app/Sources/ProtlyKeyboard/Secrets.swift
```
(`.build/` matches both packages' build folders.)

**Step 5: Placeholders so the package builds**

Create `Sources/ProtlyCore/Keys.swift` containing only `// Filled in Task 1.3.`, `Sources/protly-eval/main.swift`
containing `print("protly-eval: filled in Task 1.6")`, and `Tests/ProtlyCoreTests/HangulTests.swift` containing
only `import XCTest`. Run `swift build --package-path ios-app/ProtlyCore`. Expected: `Build complete!`.

**Step 6: Commit**

```bash
git add .gitignore ios-app/ProtlyCore
git commit -m "chore(ios): ProtlyCore package with word lists"
```

### Task 1.3: Key model and Hangul composer

**Files:**
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/Keys.swift`, `Hangul.swift`
- Test: `ios-app/ProtlyCore/Tests/ProtlyCoreTests/HangulTests.swift`

**Step 1: Write the failing tests** (`HangulTests.swift`)

```swift
import XCTest
@testable import ProtlyCore

final class HangulTests: XCTestCase {
    private func keys(_ s: String) -> [KeyEvent] {
        // Uppercase letter = manual shift (Dubeolsik double consonant or ㅒ/ㅖ).
        s.map { $0.isUppercase ? KeyEvent(Character($0.lowercased()), .manual) : KeyEvent($0) }
    }

    private func compose(_ s: String) -> String { Hangul.compose(keys(s)).text }

    func testBasicSyllables() {
        XCTAssertEqual(compose("dkssud"), "안녕")
        XCTAssertEqual(compose("gksrmf"), "한글")
        XCTAssertEqual(compose("dml"), "의")
    }

    func testFinalMovesToNextSyllable() {
        XCTAssertEqual(compose("rkrtl"), "각시")   // ㄱ+ㅅ would be ㄳ, the vowel takes ㅅ back
        XCTAssertEqual(compose("dlfrdj"), "읽어")  // ㄺ splits, ㄱ stays, ㅇ starts 어
        XCTAssertEqual(compose("djqtdj"), "없어")
        XCTAssertEqual(compose("rkqt"), "값")
    }

    func testCompoundVowels() {
        XCTAssertEqual(compose("rhk"), "과")
        XCTAssertEqual(compose("dnjs"), "원")
        XCTAssertEqual(compose("ehho"), "도ㅙ")      // ㅗ after a finished 도 starts a lone vowel; ㅗ+ㅐ = ㅙ
    }

    func testManualShiftGivesDoubleConsonant() {
        XCTAssertEqual(compose("Rk"), "까")
        XCTAssertEqual(compose("goTdj"), "했어")
        XCTAssertEqual(compose("dO"), "얘")
    }

    func testAutomaticShiftIsIgnoredInKorean() {
        let k = [KeyEvent("q", .automatic), KeyEvent("k")]
        XCTAssertEqual(Hangul.compose(k).text, "바")
        XCTAssertEqual(Dubeolsik.latin(k), "Qk")
    }

    func testBackspaceIsDropLastKey() {
        XCTAssertEqual(compose(String("rkr".dropLast())), "가")
        XCTAssertEqual(compose(String("rhk".dropLast())), "고")
        XCTAssertEqual(compose(String("dkssu".dropLast())), "안ㄴ")
    }

    func testValidity() {
        XCTAssertTrue(Hangul.compose(keys("dkssud")).isValid)
        XCTAssertTrue(Hangul.compose(keys("zzz")).isValid)          // ㅋㅋㅋ
        XCTAssertTrue(Hangul.compose(keys("whgdkzz")).isValid)      // 좋아ㅋㅋ
        XCTAssertTrue(Hangul.compose(keys("dkss")).isValid)         // 안ㄴ while typing
        XCTAssertFalse(Hangul.compose(keys("hello")).isValid)       // ㅗ first
        XCTAssertFalse(Hangul.compose(keys("ok")).isValid)          // ㅐㅏ
        XCTAssertTrue(Hangul.compose(keys("whgdkbb")).isValid)      // 좋아ㅠㅠ
    }
}
```

**Step 2: Run, expect a compile failure** (`KeyEvent`, `Hangul` undefined)

Run: `swift test --package-path ios-app/ProtlyCore --filter HangulTests`

**Step 3: Implement `Keys.swift`**

```swift
// Raw key model and the Dubeolsik (2-set) key map.
// The keyboard records keys, not characters, so one key sequence can be read as English or Korean.

public enum Shift: Sendable, Equatable {
    case none
    case manual     // the user pressed shift or caps lock
    case automatic  // auto-capitalization turned shift on
}

public struct KeyEvent: Sendable, Equatable {
    public let letter: Character  // always lowercase a-z
    public let shift: Shift

    public init(_ letter: Character, _ shift: Shift = .none) {
        self.letter = letter
        self.shift = shift
    }
}

public enum Dubeolsik {
    static let plain: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ", "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ", "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
    ]
    static let shifted: [Character: Character] = [
        "q": "ㅃ", "w": "ㅉ", "e": "ㄸ", "r": "ㄲ", "t": "ㅆ", "o": "ㅒ", "p": "ㅖ",
    ]

    /// Korean jamo for a key. Only MANUAL shift selects the shifted jamo: an auto-capitalized
    /// sentence start must never turn ㅂ into ㅃ.
    public static func jamo(for key: KeyEvent) -> Character {
        if key.shift == .manual, let s = shifted[key.letter] { return s }
        return plain[key.letter]!
    }

    /// Key string of the Korean reading: lowercase letters, uppercase only where the shifted jamo is used.
    /// This is the lookup key of the Korean word list.
    public static func koreanKeyString(_ keys: [KeyEvent]) -> String {
        String(keys.map { k in
            (k.shift == .manual && shifted[k.letter] != nil) ? Character(k.letter.uppercased()) : k.letter
        })
    }

    /// English reading: any shift capitalizes.
    public static func latin(_ keys: [KeyEvent]) -> String {
        String(keys.map { $0.shift == .none ? $0.letter : Character($0.letter.uppercased()) })
    }
}
```

**Step 4: Implement `Hangul.swift`**

```swift
// Dubeolsik composition: jamo sequence -> Hangul syllables. libhangul's 2-set rules:
// compound vowels and finals, and a final consonant moves to the next syllable when a vowel follows.
// Backspace is "drop the last key and recompose", which gives Apple's jamo-by-jamo delete.

public struct Composition: Sendable, Equatable {
    public let text: String
    /// True when every lone jamo sits in one run at the end ("좋아ㅋㅋ", "ㅇㅇ", or a lead consonant
    /// still waiting for its vowel) and that run's lone vowels are chat faces (ㅠ ㅜ ㅡ).
    /// A lone jamo before a syllable means the keys were not Korean.
    public let isValid: Bool
}

public enum Hangul {
    static let choseong: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let jungseong: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let jongseong: [Character] = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")  // index + 1
    static let vowelPairs: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    static let finalPairs: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
        "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]

    static func isVowel(_ c: Character) -> Bool { jungseong.contains(c) }

    /// Compatibility jamo block U+3131...U+318E (a lone jamo in text).
    static func isLoneJamo(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x3131...0x318E).contains(v)
    }

    static func isSyllable(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0xAC00...0xD7A3).contains(v)
    }

    public static func compose(_ keys: [KeyEvent]) -> Composition {
        compose(jamos: keys.map(Dubeolsik.jamo(for:)))
    }

    public static func compose(jamos: [Character]) -> Composition {
        var c = Composer()
        for j in jamos { c.feed(j) }
        let text = c.finish()
        // Valid when, after dropping the trailing run of lone jamo, no lone jamo is left.
        let tail = text.reversed().prefix(while: isLoneJamo)
        let head = text.reversed().drop(while: isLoneJamo)
        let faceVowels: Set<Character> = ["ㅠ", "ㅜ", "ㅡ"]
        let tailOK = tail.allSatisfy { !isVowel($0) || faceVowels.contains($0) }
        return Composition(text: text, isValid: tailOK && !head.contains(where: isLoneJamo))
    }
}

private struct Composer {
    var cho: Character?
    var jung: Character?
    var jong: [Character] = []
    var out = ""

    mutating func feed(_ j: Character) {
        Hangul.isVowel(j) ? feedVowel(j) : feedConsonant(j)
    }

    mutating func feedConsonant(_ c: Character) {
        if cho != nil, jung != nil {
            if jong.isEmpty, Hangul.jongseong.contains(c) { jong = [c]; return }
            if jong.count == 1, Hangul.finalPairs[String([jong[0], c])] != nil { jong.append(c); return }
        }
        flush()
        cho = c
    }

    mutating func feedVowel(_ v: Character) {
        if cho != nil, jung == nil { jung = v; return }
        if let cur = jung, jong.isEmpty, let pair = Hangul.vowelPairs[String([cur, v])] { jung = pair; return }
        if cho != nil, jung != nil, !jong.isEmpty {
            let moved = jong.removeLast()
            flush()
            cho = moved
            jung = v
            return
        }
        flush()
        jung = v
    }

    mutating func flush() {
        defer { cho = nil; jung = nil; jong = [] }
        switch (cho, jung) {
        case let (l?, v?):
            let li = Hangul.choseong.firstIndex(of: l)!
            let vi = Hangul.jungseong.firstIndex(of: v)!
            var ti = 0
            if !jong.isEmpty {
                let t = jong.count == 2 ? Hangul.finalPairs[String(jong)]! : jong[0]
                ti = Hangul.jongseong.firstIndex(of: t)! + 1
            }
            out.append(Character(Unicode.Scalar(UInt32(0xAC00 + (li * 21 + vi) * 28 + ti))!))
        case let (l?, nil): out.append(l)
        case let (nil, v?): out.append(v)
        case (nil, nil): break
        }
    }

    mutating func finish() -> String {
        flush()
        return out
    }
}
```

**Step 5: Run, expect 7 tests pass**

Run: `swift test --package-path ios-app/ProtlyCore --filter HangulTests`

**Step 6: Commit** `feat(ios): Dubeolsik key model and Hangul composer`

### Task 1.4: Key encoder (text to keys)

**Files:**
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/KeyEncoder.swift`
- Test: `ios-app/ProtlyCore/Tests/ProtlyCoreTests/KeyEncoderTests.swift`

The round-trip test needs `WordList.bundled` and `WordList.parse` from Task 1.5. Write `KeyEncoderTests.swift` now
without `testKoreanListRoundTrip`, and add that test in Task 1.5 Step 1.

**Step 1: Failing tests** (full file below; leave out `testKoreanListRoundTrip` until Task 1.5)

```swift
import XCTest
@testable import ProtlyCore

final class KeyEncoderTests: XCTestCase {
    func testHangulKeys() {
        XCTAssertEqual(KeyEncoder.keys(forHangul: "안녕").map(Dubeolsik.koreanKeyString), "dkssud")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "했어").map(Dubeolsik.koreanKeyString), "goTdj")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "읽어").map(Dubeolsik.koreanKeyString), "dlfrdj")
        XCTAssertEqual(KeyEncoder.keys(forHangul: "ㅋㅋ").map(Dubeolsik.koreanKeyString), "zz")
        XCTAssertNil(KeyEncoder.keys(forHangul: "TV를"))
    }

    func testLatinKeys() {
        let k = KeyEncoder.keys(forLatin: "The", sentenceStart: true)!
        XCTAssertEqual(k.first?.shift, .automatic)
        let n = KeyEncoder.keys(forLatin: "NYC", sentenceStart: false)!
        XCTAssertEqual(n.map(\.shift), [.manual, .manual, .manual])
        XCTAssertNil(KeyEncoder.keys(forLatin: "don't", sentenceStart: false))
    }

    /// Every word of the bundled Korean list must survive keys -> compose unchanged.
    func testKoreanListRoundTrip() throws {
        let text = try WordList.bundled("ko_50k")
        var checked = 0
        for (word, _) in WordList.parse(text) {
            guard let k = KeyEncoder.keys(forHangul: word) else { continue }
            XCTAssertEqual(Hangul.compose(k).text, word)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 45_000)
    }
}
```

**Step 2: Run, expect compile failure.** **Step 3: Implement:**

```swift
// Text -> key events: the inverse of the keyboard. Used to load the Korean word list (keyed by keys)
// and to turn the evaluation corpus into the keys a user would press.

public enum KeyEncoder {
    private static let keyForJamo: [Character: KeyEvent] = {
        var m: [Character: KeyEvent] = [:]
        for (k, j) in Dubeolsik.plain { m[j] = KeyEvent(k) }
        for (k, j) in Dubeolsik.shifted { m[j] = KeyEvent(k, .manual) }
        return m
    }()
    private static let splitVowel = Dictionary(uniqueKeysWithValues: Hangul.vowelPairs.map { ($0.value, Array($0.key)) })
    private static let splitFinal = Dictionary(uniqueKeysWithValues: Hangul.finalPairs.map { ($0.value, Array($0.key)) })

    /// Keys for a word made only of Hangul syllables and lone jamo. nil for anything else.
    public static func keys(forHangul word: String) -> [KeyEvent]? {
        var jamos: [Character] = []
        for ch in word {
            if Hangul.isSyllable(ch) {
                let s = Int(ch.unicodeScalars.first!.value) - 0xAC00
                let l = s / 588, v = (s % 588) / 28, t = s % 28
                jamos.append(Hangul.choseong[l])
                let vowel = Hangul.jungseong[v]
                jamos += splitVowel[vowel] ?? [vowel]
                if t > 0 {
                    let fin = Hangul.jongseong[t - 1]
                    jamos += splitFinal[fin] ?? [fin]
                }
            } else if Hangul.isLoneJamo(ch) {
                jamos += splitVowel[ch] ?? splitFinal[ch] ?? [ch]
            } else {
                return nil
            }
        }
        var keys: [KeyEvent] = []
        for j in jamos {
            guard let k = keyForJamo[j] else { return nil }
            keys.append(k)
        }
        return keys
    }

    /// Keys for an ASCII-letter word. Capitals are manual shift, except the first letter of a
    /// sentence, which auto-capitalization typed (`sentenceStart`).
    public static func keys(forLatin word: String, sentenceStart: Bool) -> [KeyEvent]? {
        var keys: [KeyEvent] = []
        for (i, ch) in word.enumerated() {
            guard ch.isASCII, ch.isLetter else { return nil }
            let lower = Character(ch.lowercased())
            if ch.isUppercase {
                keys.append(KeyEvent(lower, (i == 0 && sentenceStart) ? .automatic : .manual))
            } else {
                keys.append(KeyEvent(lower))
            }
        }
        return keys
    }
}
```

**Step 4: Run, expect pass.** **Step 5: Commit** `feat(ios): key encoder for word lists and corpus`

### Task 1.5: Word list and language detector

**Files:**
- Create: `ios-app/ProtlyCore/Sources/ProtlyCore/WordList.swift`, `LanguageDetector.swift`
- Test: `ios-app/ProtlyCore/Tests/ProtlyCoreTests/LanguageDetectorTests.swift`; add `testKoreanListRoundTrip`
  to `KeyEncoderTests.swift`

**Step 1: Failing tests**

```swift
import XCTest
@testable import ProtlyCore

final class LanguageDetectorTests: XCTestCase {
    // Tiny lists keep these tests about the rules, not about corpus counts.
    let detector = LanguageDetector(
        english: WordList(entries: [("the", 1000), ("go", 500), ("red", 100)]),
        korean: WordList(entries: [("go", 500), ("dkssud", 50)]),  // "go" = 해, "dkssud" = 안녕
        priorBonus: 2.0
    )

    private func keys(_ s: String) -> [KeyEvent] { s.map { KeyEvent($0) } }

    func testInvalidHangulIsEnglish() {
        XCTAssertEqual(detector.decide(keys("hello"), complete: true, previous: .korean), .english)
    }

    func testKnownOnlyInOneList() {
        XCTAssertEqual(detector.decide(keys("dkssud"), complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys("the"), complete: true, previous: .korean), .english)  // 솓
        XCTAssertEqual(detector.decide(keys("red"), complete: true, previous: nil), .english)      // ㄱㄷㅇ
    }

    func testUnknownValidHangulIsKorean() {
        let k = [KeyEvent("g"), KeyEvent("o"), KeyEvent("t", .manual), KeyEvent("d"), KeyEvent("j")]  // 했어
        XCTAssertEqual(detector.decide(k, complete: true, previous: .english), .korean)
        XCTAssertEqual(detector.decide(keys("zz"), complete: true, previous: nil), .korean)        // ㅋㅋ
    }

    func testPriorBreaksCloseCalls() {
        // go: 500/1600 in English vs 500/550 in Korean. Korean wins alone; the English prior flips it.
        XCTAssertEqual(detector.decide(keys("go"), complete: true, previous: nil), .korean)
        XCTAssertEqual(detector.decide(keys("go"), complete: true, previous: .english), .english)
    }

    func testPrefixWhileTyping() {
        XCTAssertEqual(detector.decide(keys("th"), complete: false, previous: nil), .english)   // only "the"
        XCTAssertEqual(detector.decide(keys("dkss"), complete: false, previous: nil), .korean)  // 안ㄴ -> 안녕
        // "g" fits English "go" and Korean ㅎ: keep the previous language, Korean at a message start.
        XCTAssertEqual(detector.decide(keys("g"), complete: false, previous: .english), .english)
        XCTAssertEqual(detector.decide(keys("g"), complete: false, previous: nil), .korean)
    }

    func testAutoShiftKeepsEnglishLookup() {
        let k = [KeyEvent("t", .automatic), KeyEvent("h"), KeyEvent("e")]
        XCTAssertEqual(detector.decide(k, complete: true, previous: nil), .english)
        XCTAssertEqual(detector.render(k, as: .english), "The")
        XCTAssertEqual(detector.render(k, as: .korean), "솓")
    }
}
```

**Step 2: Run, expect compile failure.**

**Step 3: `WordList.swift`**

```swift
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
```

**Step 4: `LanguageDetector.swift`**

```swift
import Foundation

// Decides, per word, whether a key sequence is Korean or English.
// 1. Keys that do not compose into valid Hangul are English ("hello" starts with a lone vowel ㅗ).
// 2. Otherwise compare relative frequency in each language (count / list total, because the Korean
//    list is much smaller), plus `priorBonus` for the language of the previous word.
// 3. Unknown in both lists but valid Hangul: Korean (inflected Korean words are mostly not listed).
// While typing (`complete == false`) the best word with that key prefix stands in for the word.

public enum Language: Sendable, Equatable {
    case korean, english
}

public struct LanguageDetector: Sendable {
    public let english: WordList
    public let korean: WordList
    public var priorBonus: Double

    public init(english: WordList, korean: WordList, priorBonus: Double = 2.0) {
        self.english = english
        self.korean = korean
        self.priorBonus = priorBonus
    }

    public static func bundled(priorBonus: Double = 2.0) throws -> LanguageDetector {
        LanguageDetector(
            english: .english(try WordList.bundled("en_50k")),
            korean: .korean(try WordList.bundled("ko_50k")),
            priorBonus: priorBonus
        )
    }

    public func decide(_ keys: [KeyEvent], complete: Bool, previous: Language?) -> Language {
        let hangul = Hangul.compose(keys)
        guard hangul.isValid else { return .english }
        // Chat shorthand: one jamo repeated (ㅋㅋ ㅇㅇ ㄱㄱ ㅠㅠ). "dd", "gg" also occur in English subtitles.
        if hangul.text.count >= 2, Set(hangul.text).count == 1, Hangul.isLoneJamo(hangul.text.first!) {
            return .korean
        }
        let enKey = Dubeolsik.latin(keys).lowercased()
        let koKey = Dubeolsik.koreanKeyString(keys)
        let en = complete ? english.frequency(of: enKey) : english.bestFrequency(prefix: enKey)
        let ko = complete ? korean.frequency(of: koKey) : korean.bestFrequency(prefix: koKey)
        if en == 0 { return .korean }  // unknown English, valid Hangul
        if ko == 0 { return .english }
        // While typing, both languages still fit: keep the previous word's language (no flicker).
        // At the start of a message, Korean (the user's main language).
        if !complete { return previous ?? .korean }
        var enScore = log(Double(en) / english.total)
        var koScore = log(Double(ko) / korean.total)
        if previous == .english { enScore += priorBonus }
        if previous == .korean { koScore += priorBonus }
        return koScore >= enScore ? .korean : .english
    }

    /// The text the keys produce in a language.
    public func render(_ keys: [KeyEvent], as language: Language) -> String {
        language == .english ? Dubeolsik.latin(keys) : Hangul.compose(keys).text
    }
}
```

**Step 5: Run the whole suite**

Run: `swift test --package-path ios-app/ProtlyCore`
Expected: `Executed 16 tests, with 0 failures`. The round-trip test checks more than 45,000 Korean list words.

**Step 6: Commit** `feat(ios): word lists and per-word language detector`

### Task 1.6: Corpus, evaluation tool, recorded numbers

**Files:**
- Create: `ios-app/ProtlyCore/scripts/make-corpus.sh`, `ios-app/ProtlyCore/Corpus/chat.txt`
- Create (generated): `ios-app/ProtlyCore/Corpus/tatoeba-kor.txt`, `tatoeba-eng.txt`
- Create: `ios-app/ProtlyCore/Sources/protly-eval/main.swift`
- Create: `docs/ios-keyboard-notes.md`

**Step 1: `scripts/make-corpus.sh`**

```bash
#!/usr/bin/env bash
# Samples Tatoeba Korean and English sentences into Corpus/ (deterministic: every Nth line of the export).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
for l in kor eng; do
  curl -fL -o "$tmp/$l.tsv.bz2" "https://downloads.tatoeba.org/exports/per_language/$l/${l}_sentences.tsv.bz2"
done
bzcat "$tmp/kor.tsv.bz2" | awk -F'\t' 'NR%8==0{print $3}' > Corpus/tatoeba-kor.txt
bzcat "$tmp/eng.tsv.bz2" | awk -F'\t' 'NR%900==0{print $3}' > Corpus/tatoeba-eng.txt
rm -rf "$tmp"
wc -l Corpus/tatoeba-*.txt
```
Run it. Expected roughly 1,990 Korean and 2,260 English lines (the export grows over time; the committed files
are the record).

**Step 2: `Corpus/chat.txt`** (chat-style Korean with English mixed in)

```
ㅋㅋㅋ 진짜?
ㅇㅇ 알겠어
오늘 뭐해
나 지금 gym 가는중
내일 meeting 몇시야
ok 그럼 7시에 보자
헐 대박
아 배고파 ㅠㅠ
그거 link 보내줘
너 instagram 봤어?
ㄱㄱ 지금 출발
좋아ㅋㅋ 그럼 거기서 봐
이번 주말에 party 있대
나 오늘 너무 피곤해
아직 안 끝났어
고마워 thank you so much
잘 자 good night
그 노래 playlist에 넣었어
걔 진짜 nice하더라
sorry 늦었어
아니 그게 아니라
뭐라고 했어?
나중에 call 할게
ㅎㅎ 알았어
거의 다 왔어
```

**Step 3: `Sources/protly-eval/main.swift`**

```swift
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
```

**Step 4: Run it**

Run: `swift run -c release --package-path ios-app/ProtlyCore protly-eval ios-app/ProtlyCore/Corpus`
(about 45 s). Expected at `priorBonus 2.0`, within a few tenths of a percent:

| File | Language | Accuracy | Words that switch while typing |
|---|---|---|---|
| tatoeba-kor | korean | 99.83% | 0.5% |
| tatoeba-eng | english | 99.55% | 0.8% |
| chat | korean | 98.33% | 21.7% |
| chat | english | 100% | 35.7% |

Chat switching is high by nature: those are the words where the user changes language, and they settle within
1-3 keys (one key cannot tell "r" from ㄱ). `FLIPS=1` before the command prints each switching word with its
per-key trace.

**Step 5: `docs/ios-keyboard-notes.md`**

Create it with a "Sprint 1: detector" section holding the table actually printed in Step 4 (all five bonus
values), the top error words, and the decision "priorBonus 2.0". Sprint 2 appends its phone findings here.

**Step 6: Commit** `feat(ios): detector corpus and accuracy report`

---

# Sprint 2: xtool spike on the phone (GATE)

Answers one question: can this laptop build a keyboard extension that loads on the iPhone and runs ProtlyCore,
and does KeyboardKit render inside it. Everything here is throwaway except the toolchain, the package layout and
the notes.

### Task 2.1: xtool and the SDK

**Step 1: fuse for AppImages**

`rpm -q fuse-libs || sudo dnf install -y fuse-libs` (the xtool AppImage needs libfuse2).

**Step 2: Install xtool 1.24.0**

```bash
curl -fL "https://github.com/xtool-org/xtool/releases/download/1.24.0/xtool-$(uname -m).AppImage" -o "$SCRATCH/xtool"
chmod +x "$SCRATCH/xtool" && sudo mv "$SCRATCH/xtool" /usr/local/bin/xtool
xtool --version
```

**Step 3 (USER): download Xcode 27.1**

Sign in at https://developer.apple.com/download/all/?q=Xcode with the Apple ID that will sign the app, download
`Xcode_27.1.xip` (several GB) to `~/Downloads/`. Tell Claude when it is there.

**Step 4 (USER): xtool setup (interactive: Apple ID password and 2FA)**

```
! xtool setup
```
Choose login mode `1` (Password). Enter the Apple ID, password, 2FA code. When asked for the SDK, give
`~/Downloads/Xcode_27.1.xip`. Afterwards Claude verifies: `swift sdk list` prints `darwin`, `xtool auth status`
shows logged in. Delete the .xip afterwards only if the user agrees (`xtool sdk status` first).

**Step 5 (USER): iPhone prerequisites**

Plug the iPhone in over USB, unlock it, tap Trust. Developer Mode appears under Settings > Privacy & Security
after the first install attempt; turn it on and let the phone restart.

### Task 2.2: App package skeleton, bare keyboard

**Files:**
- Create: `ios-app/Package.swift`, `ios-app/xtool.yml`, `ios-app/Support/ProtlyKeyboard-Info.plist`
- Create: `ios-app/Sources/Protly/ProtlyApp.swift`
- Create: `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`, `Spike.swift`
- Create: `ios-app/scripts/make-secrets.sh`

Code in this task cannot be compiled before the SDK exists; it is marked [UNVERIFIED] against the iOS 27 SDK.

**Step 1: `ios-app/Package.swift`** [UNVERIFIED: unsafeFlags reaching xtool's extension link]

```swift
// swift-tools-version: 6.0
import PackageDescription

// xtool app package: the container app and the keyboard extension. Logic lives in ProtlyCore.
let package = Package(
    name: "Protly",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Protly", targets: ["Protly"]),
        .library(name: "ProtlyKeyboard", targets: ["ProtlyKeyboard"]),
    ],
    dependencies: [
        .package(path: "ProtlyCore"),
    ],
    targets: [
        .target(name: "Protly"),
        .target(
            name: "ProtlyKeyboard",
            dependencies: [.product(name: "ProtlyCore", package: "ProtlyCore")],
            // xtool issues #313/#379: keep the principal class from being dead-stripped.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_OBJC_CLASS_$_KeyboardViewController"])]
        ),
    ]
)
```

**Step 2: `ios-app/xtool.yml`**

```yaml
version: 1
bundleID: com.northprot.protly
product: Protly
extensions:
  - product: ProtlyKeyboard
    infoPath: Support/ProtlyKeyboard-Info.plist
```

**Step 3: `ios-app/Support/ProtlyKeyboard-Info.plist`** (xtool merges it raw: no `$(VAR)`; the class name is
pinned with `@objc(KeyboardViewController)`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Protly</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>IsASCIICapable</key>
            <false/>
            <key>PrefersRightToLeft</key>
            <false/>
            <key>PrimaryLanguage</key>
            <string>ko-KR</string>
            <key>RequestsOpenAccess</key>
            <true/>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.keyboard-service</string>
        <key>NSExtensionPrincipalClass</key>
        <string>KeyboardViewController</string>
    </dict>
</dict>
</plist>
```

**Step 4: `ios-app/scripts/make-secrets.sh`**

```bash
#!/usr/bin/env bash
# Writes the gitignored Secrets.swift from ~/.config/protly/phone-api-key. Prints nothing secret.
set -euo pipefail
cd "$(dirname "$0")/.."
src="$HOME/.config/protly/phone-api-key"
[ -s "$src" ] || { echo "missing $src (one line: the phone's sk-ant- key, chmod 600)" >&2; exit 1; }
key="$(tr -d '[:space:]' < "$src")"
case "$key" in sk-ant-*) ;; *) echo "$src does not look like an Anthropic key" >&2; exit 1 ;; esac
out=Sources/ProtlyKeyboard/Secrets.swift
umask 077
printf '// Generated by scripts/make-secrets.sh. Gitignored. Never commit, never print.\nenum Secrets {\n    static let apiKey = "%s"\n}\n' "$key" > "$out"
git check-ignore -q "$out" || { rm -f "$out"; echo "Secrets.swift is not gitignored; refusing" >&2; exit 1; }
echo "wrote $out"
```

**USER, once:** put the phone's key (the one in the Shortcut's first Text action) in the file:
```
! mkdir -p ~/.config/protly && umask 077 && read -rsp 'phone key: ' k && printf '%s\n' "$k" > ~/.config/protly/phone-api-key && echo saved
```

**Step 5: `ios-app/Sources/Protly/ProtlyApp.swift`** [UNVERIFIED]

```swift
import SwiftUI

// Container app: setup guide and a test field. Free Apple ID teams get no App Group,
// so there is nothing to configure here.
@main
struct ProtlyApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

struct SetupView: View {
    @State private var test = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Text("1. Settings > General > Keyboard > Keyboards > Add New Keyboard > Protly")
                    Text("2. Tap Protly and turn on Allow Full Access")
                    Text("3. Keep the Emoji keyboard")
                }
                Section("Test") {
                    TextField("Type here", text: $test, axis: .vertical)
                }
            }
            .navigationTitle("Protly")
        }
    }
}
```

**Step 6: `ios-app/Sources/ProtlyKeyboard/Spike.swift`** [UNVERIFIED]

```swift
import Foundation

// Sprint 2 only: one real API call from inside the keyboard.
enum Spike {
    static let workspaceID = "wrkspc_01MYddxiRDrvfHCyhebhtnQj"  // public, same as ios/protly.cherri

    static func ping() async -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(Secrets.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-sonnet-5-5",
            "max_tokens": 20,
            "messages": [["role": "user", "content": "Reply with the single word: pong"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return "HTTP \(code) in \(ms) ms: \(String(decoding: data.prefix(120), as: UTF8.self))"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}
```

**Step 7: `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`** (bare UIKit spike, no KeyboardKit)
[UNVERIFIED]

```swift
import ProtlyCore
import UIKit

// Sprint 2 spike: proves the extension loads, ProtlyCore runs inside it, and measures what the host apps allow.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private let status = UILabel()
    private var markedStep = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        status.font = .systemFont(ofSize: 13)
        status.numberOfLines = 3
        status.text = "protly spike"
        let actions: [(String, Selector)] = [
            ("안녕", #selector(typeKorean)),
            ("Marked", #selector(typeMarked)),
            ("Context", #selector(showContext)),
            ("Clipboard", #selector(readClipboard)),
            ("API", #selector(callAPI)),
            ("Next", #selector(nextKeyboard)),
        ]
        let row = UIStackView(arrangedSubviews: actions.map { title, action in
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.addTarget(self, action: action, for: .touchUpInside)
            return b
        })
        row.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [status, row])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            view.heightAnchor.constraint(equalToConstant: 216),
        ])
    }

    @objc private func typeKorean() {
        textDocumentProxy.insertText(Hangul.compose("dkssud".map { KeyEvent($0) }).text)
    }

    // Steps through a syllable being composed, the way the real keyboard will show it.
    @objc private func typeMarked() {
        let steps = ["ㅇ", "아", "안", "안ㄴ", "안녀", "안녕"]
        if markedStep < steps.count {
            let s = steps[markedStep]
            textDocumentProxy.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
            markedStep += 1
            status.text = "marked: \(s) (tap again)"
        } else {
            textDocumentProxy.unmarkText()
            markedStep = 0
            status.text = "unmarked"
        }
    }

    @objc private func showContext() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let selected = textDocumentProxy.selectedText ?? ""
        status.text = "before \(before.count), after \(after.count), selected \(selected.count); full access \(hasFullAccess)"
    }

    @objc private func readClipboard() {
        let text = UIPasteboard.general.string ?? ""
        status.text = "clipboard \(text.count) chars, changeCount \(UIPasteboard.general.changeCount)"
    }

    @objc private func callAPI() {
        status.text = "calling..."
        Task { @MainActor in status.text = await Spike.ping() }
    }

    @objc private func nextKeyboard() { advanceToNextInputMode() }
}
```

**Step 8: Build** (no device needed)

```bash
cd ~/projects/protly/ios-app && ./scripts/make-secrets.sh && xtool dev build
```
Expected: `xtool/Protly.app` with `PlugIns/ProtlyKeyboard.appex`. Then check the class survived linking:
```bash
llvm-nm xtool/Protly.app/PlugIns/ProtlyKeyboard.appex/ProtlyKeyboard | grep -c KeyboardViewController
llvm-objdump -h xtool/Protly.app/PlugIns/ProtlyKeyboard.appex/ProtlyKeyboard | grep __text
```
Expected: count > 0 and a `__text` section. (`llvm-nm`/`llvm-objdump` ship with the swiftly toolchain.) If the
class is missing or zsign fails with "Can't find free space of LoadCommands for CodeSignature", try `-Xlinker -ObjC`
in `linkerSettings`; if both fail, record the error in the notes and stop: this is the gate failing.

**Step 9: Commit** (Secrets.swift must not be staged: `git status --short` shows no `Secrets.swift`)

`feat(ios): xtool app package with bare keyboard spike`

### Task 2.3: Install and the phone checklist (USER)

**Step 1:** phone plugged in and unlocked. Claude runs `cd ios-app && xtool dev run` (or the user runs
`! cd ~/projects/protly/ios-app && xtool dev run` if it prompts). First run: on the phone, Settings > General >
VPN & Device Management > trust the developer, and turn on Developer Mode if asked.

**Step 2: checklist.** Claude prints this list; the user reports each result; Claude records them in
`docs/ios-keyboard-notes.md` under "Sprint 2: bare spike":

1. Settings > General > Keyboard > Keyboards > Add New Keyboard: Protly is listed. Add it, open it, turn on
   Allow Full Access.
2. In the Protly app's test field, switch to Protly, tap `안녕`: "안녕" appears.
3. `API`: status shows `HTTP 200` and the time.
4. `Marked`, in Instagram DM, KakaoTalk and Messages: tap 6 times then once more. For each app: is there an
   underline or highlight while composing, does the final 안녕 stay after unmark?
5. `Context`, in Instagram DM and KakaoTalk: type a 3-paragraph draft (with Apple's keyboard), cursor at the end,
   switch to Protly, tap `Context`. Compare the before count with the real length.
6. `Clipboard`: copy a message in Instagram, come back to the composer, tap `Clipboard`. Was there an "Allow
   Paste" prompt? Is the count right? Repeat once to see if the prompt comes every time.
7. `Next` with only Protly and Emoji enabled: does it open the Emoji keyboard, and does Emoji's ABC key return to
   Protly?
8. Settings: can both Apple Korean and English keyboards be removed while Protly and Emoji stay?
9. Memory/stability: any crash or the keyboard falling back to Apple's (note when).

**Step 3: Commit** the notes: `docs: Sprint 2 bare keyboard findings`

### Task 2.4: KeyboardKit 9.9.1 vendored and patched

**Files:**
- Create: `ios-app/Vendor/KeyboardKit/` (Package.swift, LICENSE, Sources)
- Modify: `ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Styling/Color+Keyboard.swift`, `Image+Keyboard.swift`
- Modify: `ios-app/Package.swift`, `ios-app/Sources/ProtlyKeyboard/KeyboardViewController.swift`

**Step 1: Vendor the source**

```bash
cd "$SCRATCH" && git clone --depth 1 --branch 9.9.1 https://github.com/KeyboardKit/KeyboardKit.git kk-9.9.1
mkdir -p ~/projects/protly/ios-app/Vendor/KeyboardKit
cp -r kk-9.9.1/Package.swift kk-9.9.1/LICENSE kk-9.9.1/Sources ~/projects/protly/ios-app/Vendor/KeyboardKit/
cd ~/projects/protly/ios-app/Vendor/KeyboardKit
rm -rf Sources/KeyboardKit/Resources/Colors.xcassets Sources/KeyboardKit/Resources/Images.xcassets Sources/KeyboardKit/KeyboardKit.docc
printf 'Vendored KeyboardKit 9.9.1 (MIT, last full-source tag, commit a7e33ac). Never upgrade to 10.x (closed binary).\nPatched: asset catalogs removed (xtool has no actool); colors and two images defined in code.\n' > VENDORED.md
```

**Step 2: Colors in code.** Replace every `Color(.name)` in `Styling/Color+Keyboard.swift` with `KKColor.name`
and append the `KKColor` enum (values extracted from the 9.9.1 colorsets):

```bash
cd ~/projects/protly/ios-app/Vendor/KeyboardKit/Sources/KeyboardKit/Styling
sed -i -E 's/Color\(\.(keyboard[A-Za-z]+)\)/KKColor.\1/g' Color+Keyboard.swift
grep -c 'KKColor\.' Color+Keyboard.swift   # expect 13
grep -c 'Color(\.' Color+Keyboard.swift    # expect 0
cat >> Color+Keyboard.swift <<'EOF'

// protly patch: the 9.9.1 asset catalog colors, defined in code (xtool cannot compile .xcassets).
#if canImport(UIKit)
import UIKit

enum KKColor {
    private static func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    private static func gray(_ w: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(white: w, alpha: a) }

    static let keyboardBackground = dynamic(UIColor(red: 0.835, green: 0.839, blue: 0.867, alpha: 1), gray(0.173))
    static let keyboardBackgroundForDarkAppearance = dynamic(gray(0.416), gray(0.173))
    static let keyboardButtonBackground = dynamic(hex(0xFFFFFF), hex(0x6B6B6B))
    static let keyboardButtonBackgroundForColorSchemeBug = dynamic(gray(1), gray(1, 0.3))
    static let keyboardButtonBackgroundForDarkAppearance = dynamic(hex(0x979797), hex(0x979797))
    static let keyboardButtonForeground = Color(UIColor.label)
    static let keyboardButtonForegroundForDarkAppearance = dynamic(hex(0xFFFFFF), .label)
    static let keyboardButtonShadow = dynamic(gray(0, 0.3), gray(0, 0.7))
    static let keyboardDarkButtonBackground = dynamic(hex(0xABB1BA), hex(0x474747))
    static let keyboardDarkButtonBackgroundForColorSchemeBug =
        dynamic(UIColor(red: 0.702, green: 0.718, blue: 0.753, alpha: 1), gray(1, 0.1))
    static let keyboardDarkButtonBackgroundForDarkAppearance = dynamic(hex(0x757575), hex(0x757575))
}
#endif
EOF
```
If the grep counts differ, read the file and fix by hand: every `Color(.x)` must become `KKColor.x`.

**Step 3: Images in code** (`Styling/Image+Keyboard.swift`)

```bash
sed -i 's/static let keyboardEmoji = Image(.keyboardEmoji)/static let keyboardEmoji = symbol("face.smiling")/; s/static let keyboardKit = Image(.keyboardKitIcon)/static let keyboardKit = symbol("keyboard")/' Image+Keyboard.swift
grep -n 'keyboardEmoji =\|keyboardKit =' Image+Keyboard.swift
```

**Step 4: Depend on it** (`ios-app/Package.swift`): add `.package(path: "Vendor/KeyboardKit")` to `dependencies`
and `"KeyboardKit"` (as `.product(name: "KeyboardKit", package: "KeyboardKit")`) to the `ProtlyKeyboard` target.

**Step 5: KeyboardKit controller.** Replace `KeyboardViewController.swift` with the version below. The spike
buttons move into KeyboardKit's toolbar slot so the bar height is compared with Apple's predictive bar.
Signatures checked against the 9.9.1 source: `setup(for: KeyboardApp, completion:)` in
`_Keyboard/KeyboardInputViewController+SetupCore.swift:29`, `setupKeyboardView(_ view: (KeyboardInputViewController)
-> Content)` in `_Keyboard/KeyboardInputViewController.swift:142`. [UNVERIFIED: compiles under xtool.]

```swift
import KeyboardKit
import ProtlyCore
import SwiftUI
import UIKit

@objc(KeyboardViewController)
final class KeyboardViewController: KeyboardInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setup(for: KeyboardApp(name: "Protly")) { _ in }
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { controller in
            KeyboardView(
                state: controller.state,
                services: controller.services,
                buttonContent: { $0.view },
                buttonView: { $0.view },
                collapsedView: { $0.view },
                emojiKeyboard: { $0.view },
                toolbar: { _ in SpikeBar(proxy: controller.textDocumentProxy) }
            )
        }
    }
}

struct SpikeBar: View {
    let proxy: UITextDocumentProxy
    @State private var status = "protly"

    var body: some View {
        HStack {
            Text(status).font(.footnote).lineLimit(1)
            Spacer()
            Button("안녕") { proxy.insertText(Hangul.compose("dkssud".map { KeyEvent($0) }).text) }
            Button("API") { Task { status = await Spike.ping() } }
        }
        .padding(.horizontal, 12)
        .frame(height: 45)
    }
}
```

**Step 6: Build, check the class again (Task 2.2 Step 8 commands), install with `xtool dev run`.**

**Step 7 (USER): look and feel.** Record in the notes under "Sprint 2: KeyboardKit":
1. Does it load? Do keys type, callouts pop up, backspace repeat, space long-press move the cursor?
2. Screenshot the same Instagram DM with Apple's English keyboard and with Protly (portrait, dark mode), send both.
   Claude compares total height, row pitch, key shapes and the glass container from the images.
3. Any crash or fallback to Apple's keyboard.

**Step 8: Commit** `feat(ios): vendored KeyboardKit 9.9.1 with color patch`

### Task 2.5: Gate decision

Pass when ALL hold (from the notes): checklist items 1, 2, 3 pass; KeyboardKit loads and types (2.4 Step 7.1).
- Pass: mark Sprint 2 complete; run `/plan-flow` for Sprints 3-6 with the notes, adjusting the contracts below to
  what was found (marked-text look, clipboard prompt, context length, emoji route, real heights).
- Fail: write what failed and the exact errors in the notes, then stop and talk to the user. Options then:
  the paid program (then Xcode Cloud or a CI Mac signs), or patching xtool (PRs #320/#393 for the link bug).

---

# Sprints 3-6: contracts only (detailed after the gate)

### Sprint 3: Full key layout and automatic language
- Layout: Apple's English QWERTY and Korean Dubeolsik keycap sets on one grid, keycaps showing only the current
  language; numbers and symbols pages; shift (one-shot, double-tap lock, Korean ㅃㅉㄸㄲㅆㅒㅖ), auto-capitalization
  recorded as AUTOMATIC shift.
- Typing: per-key `ProtlyCore` decision (`complete: false`), composition shown with marked text (or the Sprint 2
  fallback), commit on space/punctuation, `complete: true` decision on commit; quick horizontal flick on space flips
  the last word; backspace = drop last key and recompose.
- Last language persisted in the keyboard's own UserDefaults as the `previous` for a new message.
- Emoji key per the Sprint 2 finding.
- Success: user types a mixed Korean/English DM in Instagram with no language key; height matches Apple's within
  the screenshot comparison.

### Sprint 4: Translate/Polish and the panel
- `ios/keyboard-prompt.txt` (text-only prompt, modes in/out/fix, same JSON schema), synced into the keyboard by
  `scripts/sync-ios-app.mjs` with a node test that fails on drift.
- Request builder and response parser in `ProtlyCore` with tests against fixed JSON; models hardcoded (in = Sonnet
  thinking off, out/fix = Opus adaptive); headers include `anthropic-workspace-id`.
- Predictive bar: protly icon + one action in the middle slot; panel at key-area height with result, back
  translation, Insert/Cancel; Undo after Insert; error strings from the design.
- Success: in Instagram, Korean draft -> Translate -> Insert -> the English text replaces the draft, Undo restores it.

### Sprint 5: Clipboard read
- New clipboard text (change count) while not mid-word -> Korean translation in the panel; skips Korean, URLs,
  field text, repeats. If Sprint 2 found a paste prompt every time: read only from the protly icon on an empty
  field.
- Success: copy a friend's English message in Instagram, return to the composer, translation shows without a tap
  (or with one tap in the fallback).

### Sprint 6: Completion, autocorrect, learning
- English completion and autocorrect on space (frequency rule, never for learned or lexicon words, undo by
  backspace); Korean whole-word completion on key prefixes; text replacements from `UILexicon`; learned words in the
  keyboard's container; detector re-measured with learned words.
- Memory: everything loaded stays under 15 MB (measured on device).
- Success: predictive bar shows Apple-like suggestions in both languages; corpus accuracy not below Sprint 1.
