/// The `"translation"` value of the reply's JSON while the model is still writing it (keyboard-ui 003). Fed the
/// text deltas in order, it decodes the value so far: every JSON escape, a `\uXXXX` escape cut across deltas (held
/// back until complete), surrogate pairs, any key order and any whitespace. It never shows a dangling backslash.
/// Incremental: each piece of text is read once.
public struct PartialTranslation: Sendable {
    private enum State: Sendable {
        case seekObject
        case seekKey
        case key(String, escaped: Bool)
        case colon(isTranslation: Bool)
        case value(isTranslation: Bool)
        case skipString(escaped: Bool)
        case skipNested(depth: Int, inString: Bool, escaped: Bool)
        case skipScalar
        case translation
        case done
    }

    private enum Escape: Sendable {
        case none
        case backslash
        case unicode(UInt32, digits: Int)
    }

    private var state = State.seekObject
    private var escape = Escape.none
    /// A high surrogate waiting for its low half.
    private var high: UInt32?
    private var out = ""
    private var started = false
    /// `out` grew during the current append.
    private var grew = false

    public init() {}

    /// The decoded value so far, nil before it starts.
    public var value: String? { started ? out : nil }

    /// The value in a whole text so far.
    public static func value(in text: String) -> String? {
        var p = PartialTranslation()
        p.append(text)
        return p.value
    }

    /// Reads the next piece of the model's text. true when `value` changed.
    @discardableResult
    public mutating func append(_ text: String) -> Bool {
        let wasStarted = started
        grew = false
        for s in text.unicodeScalars {
            if case .done = state { break }
            read(s)
        }
        return started != wasStarted || grew
    }

    private static func isSpace(_ s: Unicode.Scalar) -> Bool {
        s == " " || s == "\n" || s == "\r" || s == "\t"
    }

    private mutating func read(_ s: Unicode.Scalar) {
        switch state {
        case .seekObject:
            if s == "{" { state = .seekKey }
        case .seekKey:
            if s == "\"" { state = .key("", escaped: false) } else if s == "}" { state = .done }
        case .key(var key, let escaped):
            if escaped {
                key.unicodeScalars.append(s)
                state = .key(key, escaped: false)
            } else if s == "\\" {
                state = .key(key, escaped: true)
            } else if s == "\"" {
                state = .colon(isTranslation: key == "translation")
            } else {
                key.unicodeScalars.append(s)
                state = .key(key, escaped: false)
            }
        case .colon(let isTranslation):
            if s == ":" { state = .value(isTranslation: isTranslation) } else if !Self.isSpace(s) { state = .seekKey }
        case .value(let isTranslation):
            if Self.isSpace(s) { return }
            if s == "\"" {
                if isTranslation {
                    started = true
                    state = .translation
                } else {
                    state = .skipString(escaped: false)
                }
            } else if s == "{" || s == "[" {
                state = .skipNested(depth: 1, inString: false, escaped: false)
            } else {
                state = .skipScalar
            }
        case .skipString(let escaped):
            if escaped {
                state = .skipString(escaped: false)
            } else if s == "\\" {
                state = .skipString(escaped: true)
            } else if s == "\"" {
                state = .seekKey
            }
        case let .skipNested(depth, inString, escaped):
            if inString {
                state = .skipNested(depth: depth, inString: !(s == "\"" && !escaped), escaped: !escaped && s == "\\")
            } else if s == "\"" {
                state = .skipNested(depth: depth, inString: true, escaped: false)
            } else if s == "{" || s == "[" {
                state = .skipNested(depth: depth + 1, inString: false, escaped: false)
            } else if s == "}" || s == "]" {
                state = depth == 1 ? .seekKey : .skipNested(depth: depth - 1, inString: false, escaped: false)
            }
        case .skipScalar:
            if s == "," { state = .seekKey } else if s == "}" { state = .done }
        case .translation:
            readTranslation(s)
        case .done:
            break
        }
    }

    private mutating func readTranslation(_ s: Unicode.Scalar) {
        switch escape {
        case .none:
            if s == "\\" {
                escape = .backslash
            } else if s == "\"" {
                flushHigh()
                state = .done
            } else {
                emit(s)
            }
        case .backslash:
            escape = .none
            switch s {
            case "\"", "\\", "/": emit(s)
            case "b": emit("\u{8}")
            case "f": emit("\u{C}")
            case "n": emit("\n")
            case "r": emit("\r")
            case "t": emit("\t")
            case "u": escape = .unicode(0, digits: 0)
            default: break  // not a JSON escape: dropped
            }
        case let .unicode(code, digits):
            guard let digit = Self.hexValue(s) else {
                escape = .none  // a broken escape: dropped
                return
            }
            let next = code << 4 | digit
            guard digits == 3 else {
                escape = .unicode(next, digits: digits + 1)
                return
            }
            escape = .none
            unit(next)
        }
    }

    private static func hexValue(_ s: Unicode.Scalar) -> UInt32? {
        switch s.value {
        case 0x30...0x39: return s.value - 0x30
        case 0x41...0x46: return s.value - 0x41 + 10
        case 0x61...0x66: return s.value - 0x61 + 10
        default: return nil
        }
    }

    /// One decoded `\uXXXX` code unit.
    private mutating func unit(_ u: UInt32) {
        switch u {
        case 0xD800...0xDBFF:
            flushHigh()
            high = u
        case 0xDC00...0xDFFF:
            if let h = high {
                high = nil
                put(Unicode.Scalar(0x10000 + ((h - 0xD800) << 10) + (u - 0xDC00))!)
            } else {
                put("\u{FFFD}")
            }
        default:
            emit(Unicode.Scalar(u)!)
        }
    }

    private mutating func emit(_ s: Unicode.Scalar) {
        flushHigh()
        put(s)
    }

    private mutating func put(_ s: Unicode.Scalar) {
        out.unicodeScalars.append(s)
        grew = true
    }

    /// A high surrogate with no low half after it.
    private mutating func flushHigh() {
        guard high != nil else { return }
        high = nil
        put("\u{FFFD}")
    }
}
