// The space bar trackpad (typing-fixes 003, docs/research/2026-10-30-space-trackpad.md R4). Replaces KeyboardKit's
// drag math, which moved a fixed 5 pt per character with no acceleration and dropped every step while the finger
// was 50 pt above or below where it started.
//
// - Horizontal only: the finger's vertical position is ignored (vertical movement, R6, is not built).
// - Cost per grapheme by its width on screen: 6 pt for a narrow one, 12 pt for Hangul, CJK and emoji, so Korean and
//   English move the caret about equally fast.
// - The remainder carries between events: ten 1 pt moves make one 6 pt step.
// - Speed gain: 1x up to 100 pt/s, rising linearly to 3x at 600 pt/s and capped there. The gain scales each move,
//   not the remainder carried from earlier ones.
// - Offsets are UTF-16 units of whole graphemes (what adjustTextPosition takes), so the caret never lands inside
//   an emoji.
// - The text is a snapshot taken at drag start; the caret stops at its ends, and a push past an end is dropped so
//   the way back starts at once.

public struct SpaceTrackpad: Sendable {
    public static let pointsPerNarrow = 6.0
    public static let pointsPerWide = 12.0
    /// At or below this speed (pt/s) the gain is 1.
    public static let slowSpeed = 100.0
    /// At or above this speed (pt/s) the gain is `maxGain`.
    public static let fastSpeed = 600.0
    public static let maxGain = 3.0
    /// The hold before space becomes the trackpad (R3). Other keys keep KeyboardKit's 0.5 s.
    public static let longPressDelay = 0.4
    /// The shortest time between two events used for the speed: one frame at 120 Hz. Events that arrive closer
    /// together (late main-thread callbacks) would otherwise read as a flick and speed up a slow drag.
    static let minInterval = 1.0 / 120

    private struct Glyph: Sendable {
        let cost: Double
        let units: Int
    }

    /// The snapshot's graphemes, before and after the caret.
    private let glyphs: [Glyph]
    /// The caret's index in `glyphs`.
    private var caret: Int
    /// Points moved toward the next grapheme, after the gain (negative: to the left).
    public private(set) var remainder = 0.0
    /// The previous tracked event: x and time.
    private var last: (x: Double, time: Double)?

    /// `before` and `after` are the text on each side of the caret when the drag starts.
    public init(before: String, after: String) {
        let left = before.map(Self.glyph)
        glyphs = left + after.map(Self.glyph)
        caret = left.count
    }

    /// A move of `dx` points (positive: right) over `dt` seconds. Returns the caret move in UTF-16 units.
    public mutating func move(dx: Double, dt: Double) -> Int {
        guard dx != 0, dx.isFinite else { return 0 }
        let interval = max(dt.isNaN ? .infinity : dt, Self.minInterval)  // no usable time: slow
        remainder += dx * Self.gain(speed: abs(dx) / interval)
        var offset = 0
        while remainder > 0 {
            guard caret < glyphs.count else {
                remainder = 0
                break
            }
            let g = glyphs[caret]
            guard remainder >= g.cost else { break }
            remainder -= g.cost
            offset += g.units
            caret += 1
        }
        while remainder < 0 {
            guard caret > 0 else {
                remainder = 0
                break
            }
            let g = glyphs[caret - 1]
            guard -remainder >= g.cost else { break }
            remainder += g.cost
            offset -= g.units
            caret -= 1
        }
        return offset
    }

    /// The finger is at (`x`, `y`) at `time` (seconds). The first event only sets the start. `y` is ignored on
    /// purpose: a thumb drifting up or down keeps moving the caret (R1).
    public mutating func track(x: Double, y: Double, time: Double) -> Int {
        let previous = last
        last = (x, time)
        guard let previous else { return 0 }
        return move(dx: x - previous.x, dt: time - previous.time)
    }

    /// 1 up to `slowSpeed`, `maxGain` from `fastSpeed`, linear between.
    static func gain(speed: Double) -> Double {
        if speed <= slowSpeed { return 1 }
        if speed >= fastSpeed { return maxGain }
        return 1 + (maxGain - 1) * (speed - slowSpeed) / (fastSpeed - slowSpeed)
    }

    /// Points of finger travel to cross one grapheme.
    static func cost(of c: Character) -> Double {
        isWide(c) ? pointsPerWide : pointsPerNarrow
    }

    private static func glyph(_ c: Character) -> Glyph {
        Glyph(cost: cost(of: c), units: c.utf16.count)
    }

    /// Hangul, CJK, fullwidth forms and emoji: about twice a Latin letter's width.
    static func isWide(_ c: Character) -> Bool {
        guard let first = c.unicodeScalars.first else { return false }
        let p = first.properties
        if p.isEmojiPresentation { return true }
        // A text-default emoji shown as emoji (❤️, 1️⃣): VS16 follows it.
        if p.isEmoji, c.unicodeScalars.contains("\u{FE0F}") { return true }
        switch first.value {
        case 0x1100...0x11FF,  // Hangul Jamo
             0x2E80...0xA4CF,  // CJK radicals and symbols, kana, Hangul compatibility jamo, CJK ideographs, Yi
             0xA960...0xA97F,  // Hangul Jamo Extended-A
             0xAC00...0xD7FF,  // Hangul syllables, Jamo Extended-B
             0xF900...0xFAFF,  // CJK compatibility ideographs
             0xFE30...0xFE4F,  // CJK compatibility forms
             0xFF00...0xFF60, 0xFFE0...0xFFE6,  // fullwidth forms
             0x20000...0x3FFFD:  // CJK ideographs, planes 2 and 3
            return true
        default:
            return false
        }
    }

    /// The text before the caret at drag start, from Protly's model rather than a proxy read made after the
    /// commit, which may not show it yet. `context` is the proxy's text before the cursor read before the commit,
    /// `written` the word being typed as it is in the field ("" for none), `committed` what the commit turned it
    /// into (nil when nothing was committed: no word, or the field moved under it and it was abandoned).
    public static func textBefore(context: String, written: String, committed: String?) -> String {
        guard let committed, !written.isEmpty, context.hasSuffix(written) else { return context }
        return String(context.dropLast(written.count)) + committed
    }
}

/// One space drag at a time: the trackpad of the drag in progress and the start location of the touch that made
/// it. The keyboard resets it on a space press, release or end; a touch the system cancels mid-drag (a notification,
/// Control Center, a system gesture) may send none of them, so a new start location resets it too. Otherwise the
/// next drag would move from the old text and the old finger position.
public struct SpaceDrag: Sendable {
    private var trackpad: SpaceTrackpad?
    private var start: (x: Double, y: Double)?

    public init() {}

    /// A trackpad is in use.
    public var isActive: Bool { trackpad != nil }

    public mutating func reset() {
        trackpad = nil
        start = nil
    }

    /// A drag event while space is the trackpad. `startX`, `startY`: where the touch began (the same for every event
    /// of one touch). `snapshot` is called once per drag, on its first event, which only sets the start. Returns the
    /// caret move in UTF-16 units.
    public mutating func move(startX: Double, startY: Double, x: Double, y: Double, time: Double,
                              snapshot: () -> SpaceTrackpad) -> Int {
        if let s = start, s.x != startX || s.y != startY { reset() }
        var pad = trackpad ?? snapshot()
        if trackpad == nil { start = (startX, startY) }
        let offset = pad.track(x: x, y: y, time: time)
        trackpad = pad
        return offset
    }
}
