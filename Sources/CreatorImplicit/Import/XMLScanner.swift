import CreatorGraph
import Foundation

/// A pull scanner over the bytes of an XML document (mesh import spec, Reading): start and end elements, with each element's
/// attributes left as byte ranges and nothing allocated per element (the stack of open names grows once). It is what a 3MF's model is
/// read with, a million vertices at a time, so it builds no strings and no dictionaries; `attributes(of:)` walks an element's
/// attributes where they lie and `decoded(_:)` makes a `String` (with entities resolved) for the few values that need one.
///
/// The document is untrusted. A `DOCTYPE` is refused (so there are no entities of the file's own to expand), nesting is held to
/// `maximumDepth`, names must match, and every way to be wrong is a `MeshImportProblem.malformedModel`; nothing traps. Namespaces are
/// not resolved here: an element's name is its literal text, prefix included. Comments, processing instructions and CDATA are skipped,
/// and so is text between elements. The five predefined entities and numeric ones are understood in `decoded(_:)`; a leading byte
/// order mark is skipped.
struct XMLScanner {
    /// The deepest nesting of elements accepted.
    static let maximumDepth = 256

    struct Tag {
        /// The element's name as written, `prefix:local` included.
        var name: Range<Int>
        /// Everything between the name and the closing `>` (or `/>`): zero or more attributes.
        var attributes: Range<Int>
    }

    enum Event {
        case start(Tag)
        /// The name of the element that closes (a self-closing element gives its start, then this).
        case end(Range<Int>)
    }

    struct Attribute {
        var name: Range<Int>
        /// The value between the quotes, entities not resolved.
        var value: Range<Int>
    }

    let bytes: UnsafeRawBufferPointer
    let typed: UnsafeBufferPointer<UInt8>
    private var position = 0
    private var open: [Range<Int>] = []
    private var pendingEnd: Range<Int>?
    private var sawRoot = false

    init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
        typed = bytes.assumingMemoryBound(to: UInt8.self)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { position = 3 }
    }

    /// How many elements are open now.
    var depth: Int { open.count }

    // MARK: Events

    /// The next start or end of an element, or `nil` at the end of a complete document.
    mutating func next() throws -> Event? {
        if let name = pendingEnd {
            pendingEnd = nil
            return .end(name)
        }
        while true {
            guard position < bytes.count else {
                if !open.isEmpty { throw Self.damaged("it stops inside an element.") }
                if !sawRoot { throw Self.damaged("it holds no model.") }
                return nil
            }
            if let event = try step() { return event }
        }
    }

    /// Skips text, a comment, a declaration or an instruction (and gives `nil`), or reads a tag.
    private mutating func step() throws -> Event? {
        guard bytes[position] == Self.lessThan else {
            try skipText()
            return nil
        }
        guard position + 1 < bytes.count else { throw Self.damaged("it stops inside a tag.") }
        switch bytes[position + 1] {
        case UInt8(ascii: "!"): try skipDeclaration()
        case UInt8(ascii: "?"): try skipInstruction()
        case UInt8(ascii: "/"): return try endTag()
        default: return try startTag()
        }
        return nil
    }

    // MARK: Pieces

    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")

    static func damaged(_ reason: String) -> MeshImportProblem { .malformedModel(reason) }

    static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }

    static func endsName(_ byte: UInt8) -> Bool {
        isSpace(byte) || byte == UInt8(ascii: "/") || byte == greaterThan || byte == UInt8(ascii: "=") || byte == lessThan
            || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'")
    }

    /// Text up to the next tag. Outside the root element only white space may stand.
    private mutating func skipText() throws {
        let inside = !open.isEmpty
        while position < bytes.count, bytes[position] != Self.lessThan {
            if !inside, !Self.isSpace(bytes[position]) { throw Self.damaged("it has text outside the model.") }
            position += 1
        }
    }

    private func find(_ pattern: StaticString, from start: Int) -> Int? {
        let length = pattern.utf8CodeUnitCount
        guard length > 0, bytes.count >= length else { return nil }
        let first = pattern.utf8Start[0]
        var index = start
        while index <= bytes.count - length {
            if bytes[index] == first, memcmp(bytes.baseAddress.unsafelyUnwrapped + index, pattern.utf8Start, length) == 0 { return index }
            index += 1
        }
        return nil
    }

    /// A comment or CDATA section is skipped; anything else starting `<!` (a DOCTYPE) is refused.
    private mutating func skipDeclaration() throws {
        if matches("<!--", at: position) {
            guard let close = find("-->", from: position + 4) else { throw Self.damaged("a comment never ends.") }
            position = close + 3
        } else if matches("<![CDATA[", at: position) {
            guard !open.isEmpty else { throw Self.damaged("it has text outside the model.") }
            guard let close = find("]]>", from: position + 9) else { throw Self.damaged("a CDATA section never ends.") }
            position = close + 3
        } else if matches("<!DOCTYPE", at: position) {
            throw Self.damaged("it has a DOCTYPE, which isn't supported.")
        } else {
            throw Self.damaged("it has a declaration this reader doesn't know.")
        }
    }

    /// `<? ... ?>`. The XML declaration may not name an encoding of 16 or 32 bits.
    private mutating func skipInstruction() throws {
        guard let close = find("?>", from: position + 2) else { throw Self.damaged("a processing instruction never ends.") }
        if matches("<?xml", at: position), position + 5 < bytes.count, Self.isSpace(bytes[position + 5]) {
            let declaration = UnsafeRawBufferPointer(rebasing: bytes[position..<close]).map { $0 | 0x20 }  // ASCII lower case
            for banned in ["utf-16", "utf-32", "ucs-2", "ucs-4", "utf16", "utf32"] where Self.contains(declaration, banned) {
                throw Self.damaged("it is \(banned.uppercased()) text, which isn't supported.")
            }
        }
        position = close + 2
    }

    private static func contains(_ haystack: [UInt8], _ needle: String) -> Bool {
        let wanted = Array(needle.utf8)
        guard haystack.count >= wanted.count else { return false }
        return (0...(haystack.count - wanted.count)).contains { haystack[$0..<($0 + wanted.count)].elementsEqual(wanted) }
    }

    private func matches(_ text: StaticString, at index: Int) -> Bool {
        let length = text.utf8CodeUnitCount
        guard index >= 0, index + length <= bytes.count else { return false }
        return memcmp(bytes.baseAddress.unsafelyUnwrapped + index, text.utf8Start, length) == 0
    }

    private mutating func endTag() throws -> Event {
        let start = position + 2
        var index = start
        while index < bytes.count, !Self.endsName(bytes[index]) { index += 1 }
        let name = start..<index
        while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == Self.greaterThan else { throw Self.damaged("an end tag is cut short.") }
        guard let expected = open.last, equal(expected, name) else { throw Self.damaged("an element is closed out of order.") }
        open.removeLast()
        position = index + 1
        return .end(name)
    }

    private mutating func startTag() throws -> Event {
        if open.isEmpty, sawRoot { throw Self.damaged("it has more than one model.") }
        var index = position + 1
        let nameStart = index
        while index < bytes.count, !Self.endsName(bytes[index]) { index += 1 }
        guard index > nameStart else { throw Self.damaged("a tag has no name.") }
        let name = nameStart..<index
        let (attributes, selfClosing, next) = try scanAttributes(from: index)
        guard open.count < Self.maximumDepth else { throw Self.damaged("its elements nest too deeply.") }
        sawRoot = true
        position = next
        if selfClosing { pendingEnd = name } else { open.append(name) }
        return .start(Tag(name: name, attributes: attributes))
    }

    /// Checks the attributes from `start` to the tag's end: their range, whether the tag closes itself, and where the next byte is.
    private func scanAttributes(from start: Int) throws -> (Range<Int>, Bool, Int) {
        var index = start
        while true {
            while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
            guard index < bytes.count else { throw Self.damaged("it stops inside a tag.") }
            switch bytes[index] {
            case Self.greaterThan:
                return (start..<index, false, index + 1)
            case UInt8(ascii: "/"):
                guard index + 1 < bytes.count, bytes[index + 1] == Self.greaterThan else { throw Self.damaged("a tag is not well formed.") }
                return (start..<index, true, index + 2)
            default:
                index = try skipAttribute(at: index)
            }
        }
    }

    /// Checks one `name = "value"` at `start` and returns where it ends.
    private func skipAttribute(at start: Int) throws -> Int {
        var index = start
        while index < bytes.count, !Self.endsName(bytes[index]) { index += 1 }
        guard index > start else { throw Self.damaged("a tag is not well formed.") }
        while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { throw Self.damaged("an attribute has no value.") }
        index += 1
        while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'") else {
            throw Self.damaged("an attribute's value isn't quoted.")
        }
        let quote = bytes[index]
        index += 1
        while index < bytes.count, bytes[index] != quote {
            if bytes[index] == Self.lessThan { throw Self.damaged("an attribute's value holds a “<”.") }
            index += 1
        }
        guard index < bytes.count else { throw Self.damaged("an attribute's value never ends.") }
        return index + 1
    }
}
