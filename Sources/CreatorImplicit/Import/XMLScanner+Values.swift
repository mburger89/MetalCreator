import CreatorGraph
import Foundation

/// Reading what a tag holds: attributes where they lie, numbers, and text with entities resolved.
extension XMLScanner {
    // MARK: Reading what a tag holds

    /// The attributes of `tag`, in file order.
    func attributes(of tag: Tag) -> Attributes {
        Attributes(bytes: bytes, position: tag.attributes.lowerBound, end: tag.attributes.upperBound)
    }

    struct Attributes: Sequence, IteratorProtocol {
        let bytes: UnsafeRawBufferPointer
        var position: Int
        let end: Int

        mutating func next() -> Attribute? {
            while position < end, XMLScanner.isSpace(bytes[position]) { position += 1 }
            guard position < end else { return nil }
            let nameStart = position
            while position < end, !XMLScanner.endsName(bytes[position]) { position += 1 }
            let name = nameStart..<position
            // The tag was checked when it was scanned: `=`, a quote and the closing quote are there.
            while position < end, bytes[position] != UInt8(ascii: "=") { position += 1 }
            position += 1
            while position < end, XMLScanner.isSpace(bytes[position]) { position += 1 }
            guard position < end else { return nil }
            let quote = bytes[position]
            position += 1
            let valueStart = position
            while position < end, bytes[position] != quote { position += 1 }
            let value = valueStart..<Swift.min(position, end)
            position += 1
            return Attribute(name: name, value: value)
        }
    }

    /// Whether the bytes in `range` are exactly `text`.
    func equals(_ range: Range<Int>, _ text: StaticString) -> Bool {
        range.count == text.utf8CodeUnitCount
            && memcmp(bytes.baseAddress.unsafelyUnwrapped + range.lowerBound, text.utf8Start, range.count) == 0
    }

    /// Whether two ranges of the document hold the same bytes.
    func equal(_ first: Range<Int>, _ second: Range<Int>) -> Bool {
        first.count == second.count
            && (first.isEmpty || memcmp(bytes.baseAddress.unsafelyUnwrapped + first.lowerBound,
                                         bytes.baseAddress.unsafelyUnwrapped + second.lowerBound, first.count) == 0)
    }

    /// Whether the bytes in `range` start with `text`.
    func hasPrefix(_ range: Range<Int>, _ text: StaticString) -> Bool {
        range.count >= text.utf8CodeUnitCount && memcmp(bytes.baseAddress.unsafelyUnwrapped + range.lowerBound, text.utf8Start,
                                                         text.utf8CodeUnitCount) == 0
    }

    /// Whether the bytes in `range` end with `text`.
    func hasSuffix(_ range: Range<Int>, _ text: StaticString) -> Bool {
        range.count >= text.utf8CodeUnitCount
            && memcmp(bytes.baseAddress.unsafelyUnwrapped + range.upperBound - text.utf8CodeUnitCount, text.utf8Start,
                      text.utf8CodeUnitCount) == 0
    }

    /// Whether the bytes in `range` hold `text` anywhere.
    func contains(_ range: Range<Int>, _ text: StaticString) -> Bool {
        let length = text.utf8CodeUnitCount
        guard length > 0, range.count >= length else { return false }
        for start in range.lowerBound...(range.upperBound - length)
        where bytes[start] == text.utf8Start[0] && memcmp(bytes.baseAddress.unsafelyUnwrapped + start, text.utf8Start, length) == 0 {
            return true
        }
        return false
    }

    /// The finite number written in `range` (`ASCIINumber`'s grammar: locale independent), or `nil`.
    func double(_ range: Range<Int>) -> Double? { ASCIINumber.parseDouble(typed, range) }

    /// `double` narrowed to a `Float`; `nil` when it does not fit.
    func float(_ range: Range<Int>) -> Float? { ASCIINumber.parse(typed, range) }

    /// Whether `byte` separates the numbers of a list.
    static func separates(_ byte: UInt8) -> Bool { isSpace(byte) }

    /// A non-negative whole number written in decimal digits alone, else `nil` (also for one that does not fit).
    func integer(_ range: Range<Int>) -> Int? {
        guard !range.isEmpty, range.count <= 18 else { return nil }
        var value = 0
        for index in range {
            let digit = bytes[index]
            guard digit >= 0x30, digit <= 0x39 else { return nil }
            value = value * 10 + Int(digit - 0x30)
        }
        return value
    }

    /// The text of `range` as it is written (entities not resolved; bytes that are not UTF-8 become replacement characters).
    func text(_ range: Range<Int>) -> String {
        // The bytes are a buffer slice, not `Data`; the rule's advice (a failable initializer) would lose the text.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: bytes[range], as: UTF8.self)
    }

    /// The start of `range` as a piece of the file's text for a message: at most `MeshImportProblem.longestQuote` characters, and the
    /// rest of a long range is never read.
    func quoted(_ range: Range<Int>) -> String {
        let bytesNeeded = 4 * (MeshImportProblem.longestQuote + 1)
        let cut = range.lowerBound..<Swift.min(range.upperBound, range.lowerBound + bytesNeeded)
        let piece = text(cut)
        let limit = MeshImportProblem.longestQuote
        return cut.count < range.count || piece.count > limit ? String(piece.prefix(limit)) + "…" : piece
    }

    /// The text of `range` with the predefined and numeric entities resolved.
    func decoded(_ range: Range<Int>) throws -> String {
        var result = [UInt8]()
        result.reserveCapacity(range.count)
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "&") else {
                result.append(byte)
                index += 1
                continue
            }
            var close = index + 1
            while close < range.upperBound, bytes[close] != UInt8(ascii: ";"), close - index <= 12 { close += 1 }
            guard close < range.upperBound, bytes[close] == UInt8(ascii: ";") else {
                throw Self.damaged("it has an “&” that isn't an entity.")
            }
            let name = UnsafeRawBufferPointer(rebasing: bytes[(index + 1)..<close])
            result += try Self.expand(name)
            index = close + 1
        }
        return String(bytes: result, encoding: .utf8) ?? ""
    }

    private static func expand(_ name: UnsafeRawBufferPointer) throws -> [UInt8] {
        switch String(bytes: name, encoding: .utf8) ?? "" {
        case "lt": return [UInt8(ascii: "<")]
        case "gt": return [UInt8(ascii: ">")]
        case "amp": return [UInt8(ascii: "&")]
        case "quot": return [UInt8(ascii: "\"")]
        case "apos": return [UInt8(ascii: "'")]
        default: break
        }
        guard name.count >= 2, name[0] == UInt8(ascii: "#") else { throw damaged("it has an entity this reader doesn't know.") }
        let hex = name[1] == UInt8(ascii: "x")
        let digits = name.dropFirst(hex ? 2 : 1)
        guard !digits.isEmpty, let code = UInt32(String(bytes: digits, encoding: .utf8) ?? "", radix: hex ? 16 : 10),
              let scalar = Unicode.Scalar(code), code != 0 else { throw damaged("it has a character reference out of range.") }
        return Array(String(Character(scalar)).utf8)
    }
}
