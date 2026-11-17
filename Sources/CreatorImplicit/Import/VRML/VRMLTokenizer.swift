import CreatorGraph
import Foundation

/// Splits VRML text into tokens: `#` comments run to the end of the line, whitespace and commas separate, `{ } [ ]` stand alone,
/// a quoted string (with `\\"` escapes) is one token, and everything else is a word, which the parser reads as a name or a number.
/// Works on bytes and never allocates; `isCancelled` is asked every 65,536 tokens.
struct VRMLTokenizer {
    enum Token: Equatable {
        case openBrace, closeBrace, openBracket, closeBracket
        case word(Range<Int>)
        case string
    }

    let bytes: UnsafeBufferPointer<UInt8>
    var index = 0
    private var tokens = 0

    init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

    private static func isSeparator(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) || byte == 0x2C
    }

    private static func endsWord(_ byte: UInt8) -> Bool {
        isSeparator(byte) || byte == 0x7B || byte == 0x7D || byte == 0x5B || byte == 0x5D || byte == 0x22 || byte == 0x23
    }

    /// The next token, or `nil` at the end of the text.
    mutating func next(isCancelled: () -> Bool) throws -> Token? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        tokens += 1
        if tokens % 65_536 == 0, isCancelled() { throw CancellationError() }
        switch bytes[index] {
        case 0x7B: index += 1; return .openBrace
        case 0x7D: index += 1; return .closeBrace
        case 0x5B: index += 1; return .openBracket
        case 0x5D: index += 1; return .closeBracket
        case 0x22: try skipString(); return .string
        default:
            let start = index
            while index < bytes.count, !Self.endsWord(bytes[index]) { index += 1 }
            return .word(start..<index)
        }
    }

    private mutating func skipSeparators() {
        while index < bytes.count {
            if Self.isSeparator(bytes[index]) {
                index += 1
            } else if bytes[index] == 0x23 {
                while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }
            } else {
                return
            }
        }
    }

    private mutating func skipString() throws {
        index += 1
        while index < bytes.count, bytes[index] != 0x22 { index += bytes[index] == 0x5C ? 2 : 1 }
        guard index < bytes.count else { throw VRMLReader.endsEarly }
        index += 1
    }

    /// The next token without taking it.
    func peeked(isCancelled: () -> Bool) throws -> Token? {
        var copy = self
        return try copy.next(isCancelled: isCancelled)
    }

    func equals(_ range: Range<Int>, _ word: StaticString) -> Bool {
        guard range.count == word.utf8CodeUnitCount else { return false }
        return word.withUTF8Buffer { expected in
            for offset in 0..<expected.count where bytes[range.lowerBound + offset] != expected[offset] { return false }
            return true
        }
    }

    /// A word's text, for names; one longer than 64 bytes is a name nothing uses and reads as "?".
    func text(_ range: Range<Int>) -> String {
        range.count > 64 ? "?" : String(bytes: bytes[range], encoding: .utf8) ?? "?"
    }

    /// Whether the word is a number (it starts like one); `number` then reads it or the file has a bad one.
    func looksNumeric(_ range: Range<Int>) -> Bool {
        let byte = bytes[range.lowerBound]
        return (byte >= 0x30 && byte <= 0x39) || byte == 0x2B || byte == 0x2D || byte == 0x2E
    }

    func number(_ range: Range<Int>) throws -> Float {
        guard let value = ASCIINumber.parse(bytes, range) else { throw VRMLReader.badNumber }
        return value
    }
}
