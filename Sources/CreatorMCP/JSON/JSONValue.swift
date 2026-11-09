import Foundation

/// A JSON document as a value. Integers that arrive as integers stay `.int`, so an ID or a count never prints as `7.0`.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    public var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// An integer, or a number with no fraction that fits one.
    public var int: Int? {
        switch self {
        case .int(let value): return value
        case .number(let value):
            guard value.isFinite, value == value.rounded(), abs(value) < 9.0e18 else { return nil }
            return Int(value)
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .number(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(data))
        return try parser.parseDocument()
    }

    /// Compact JSON with sorted keys and no trailing newline.
    public func encoded() -> Data {
        var out: [UInt8] = []
        write(into: &out)
        return Data(out)
    }

    /// The compact JSON as text.
    public var text: String { String(bytes: encoded(), encoding: .utf8) ?? "" }

    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try single.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null: try single.encodeNil()
        case .bool(let value): try single.encode(value)
        case .int(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .string(let value): try single.encode(value)
        case .array(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        }
    }
}

extension JSONValue {
    fileprivate func write(into out: inout [UInt8]) {
        switch self {
        case .null: out += Array("null".utf8)
        case .bool(let value): out += Array((value ? "true" : "false").utf8)
        case .int(let value): out += Array(String(value).utf8)
        case .number(let value): out += Array((value.isFinite ? "\(value)" : "null").utf8)
        case .string(let value): Self.write(string: value, into: &out)
        case .array(let items): Self.write(array: items, into: &out)
        case .object(let members): Self.write(object: members, into: &out)
        }
    }

    private static func write(array items: [JSONValue], into out: inout [UInt8]) {
        out.append(0x5B)
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(0x2C) }
            item.write(into: &out)
        }
        out.append(0x5D)
    }

    private static func write(object members: [String: JSONValue], into out: inout [UInt8]) {
        out.append(0x7B)
        for (index, key) in members.keys.sorted().enumerated() {
            if index > 0 { out.append(0x2C) }
            write(string: key, into: &out)
            out.append(0x3A)
            members[key]?.write(into: &out)
        }
        out.append(0x7D)
    }

    private static func write(string: String, into out: inout [UInt8]) {
        out.append(0x22)
        for byte in string.utf8 {
            switch byte {
            case 0x22: out += Array("\\\"".utf8)
            case 0x5C: out += Array("\\\\".utf8)
            case 0x0A: out += Array("\\n".utf8)
            case 0x0D: out += Array("\\r".utf8)
            case 0x09: out += Array("\\t".utf8)
            case 0..<0x20:
                let hex = String(byte, radix: 16)
                out += Array("\\u00\(hex.count == 1 ? "0" : "")\(hex)".utf8)
            default: out.append(byte)
            }
        }
        out.append(0x22)
    }
}

/// A JSON syntax error.
public struct JSONParseError: Error, Equatable, Sendable {
    public let message: String
}

/// A strict RFC 8259 parser over UTF-8 bytes. Nesting is limited so a hostile line cannot exhaust the stack.
private struct JSONParser {
    let bytes: [UInt8]
    var position = 0
    static let maximumDepth = 256

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> JSONValue {
        guard String(validating: bytes, as: UTF8.self) != nil else {
            throw JSONParseError(message: "The text isn't valid UTF-8.")
        }
        let value = try parseValue(depth: 0)
        skipSpace()
        guard position == bytes.count else { throw fail("Unexpected text after the value") }
        return value
    }

    private func fail(_ what: String) -> JSONParseError {
        JSONParseError(message: "\(what) at byte \(position).")
    }

    private mutating func skipSpace() {
        while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) { position += 1 }
    }

    private mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth < Self.maximumDepth else { throw fail("Nested too deeply") }
        skipSpace()
        guard position < bytes.count else { throw fail("Unexpected end") }
        switch bytes[position] {
        case 0x7B: return try parseObject(depth: depth)
        case 0x5B: return try parseArray(depth: depth)
        case 0x22: return .string(try parseString())
        case 0x74: try expect("true"); return .bool(true)
        case 0x66: try expect("false"); return .bool(false)
        case 0x6E: try expect("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func expect(_ word: String) throws {
        let letters = Array(word.utf8)
        guard position + letters.count <= bytes.count, Array(bytes[position..<position + letters.count]) == letters else {
            throw fail("Unexpected text")
        }
        position += letters.count
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        position += 1
        var members: [String: JSONValue] = [:]
        skipSpace()
        if position < bytes.count, bytes[position] == 0x7D { position += 1; return .object(members) }
        while true {
            skipSpace()
            guard position < bytes.count, bytes[position] == 0x22 else { throw fail("Expected a key") }
            let key = try parseString()
            skipSpace()
            guard position < bytes.count, bytes[position] == 0x3A else { throw fail("Expected a colon") }
            position += 1
            members[key] = try parseValue(depth: depth + 1)
            skipSpace()
            guard position < bytes.count else { throw fail("Unexpected end") }
            if bytes[position] == 0x2C { position += 1; continue }
            if bytes[position] == 0x7D { position += 1; return .object(members) }
            throw fail("Expected a comma or a closing brace")
        }
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        position += 1
        var items: [JSONValue] = []
        skipSpace()
        if position < bytes.count, bytes[position] == 0x5D { position += 1; return .array(items) }
        while true {
            items.append(try parseValue(depth: depth + 1))
            skipSpace()
            guard position < bytes.count else { throw fail("Unexpected end") }
            if bytes[position] == 0x2C { position += 1; continue }
            if bytes[position] == 0x5D { position += 1; return .array(items) }
            throw fail("Expected a comma or a closing bracket")
        }
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard position + 4 <= bytes.count else { throw fail("Unexpected end") }
        var value: UInt32 = 0
        for byte in bytes[position..<position + 4] {
            guard let digit = Character(UnicodeScalar(byte)).hexDigitValue else { throw fail("Bad escape") }
            value = value * 16 + UInt32(digit)
        }
        position += 4
        return value
    }

    private mutating func parseString() throws -> String {
        position += 1
        var out: [UInt8] = []
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            switch byte {
            case 0x22: return String(bytes: out, encoding: .utf8) ?? ""
            case 0x5C: try parseEscape(into: &out)
            case 0..<0x20: throw fail("Control character in a string")
            default: out.append(byte)
            }
        }
        throw fail("Unterminated string")
    }

    private mutating func parseEscape(into out: inout [UInt8]) throws {
        guard position < bytes.count else { throw fail("Unexpected end") }
        let escape = bytes[position]
        position += 1
        switch escape {
        case 0x22, 0x5C, 0x2F: out.append(escape)
        case 0x62: out.append(0x08)
        case 0x66: out.append(0x0C)
        case 0x6E: out.append(0x0A)
        case 0x72: out.append(0x0D)
        case 0x74: out.append(0x09)
        case 0x75: out += Array(String(Character(try parseUnicodeEscape())).utf8)
        default: throw fail("Bad escape")
        }
    }

    private mutating func parseUnicodeEscape() throws -> UnicodeScalar {
        var code = try parseHex4()
        if (0xD800..<0xDC00).contains(code) {
            guard position + 1 < bytes.count, bytes[position] == 0x5C, bytes[position + 1] == 0x75 else {
                throw fail("Unpaired surrogate")
            }
            position += 2
            let low = try parseHex4()
            guard (0xDC00..<0xE000).contains(low) else { throw fail("Unpaired surrogate") }
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
        }
        guard let scalar = UnicodeScalar(code) else { throw fail("Bad escape") }
        return scalar
    }

    private mutating func skipDigits() -> Int {
        let start = position
        while position < bytes.count, (0x30...0x39).contains(bytes[position]) { position += 1 }
        return position - start
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = position
        var isInteger = true
        if position < bytes.count, bytes[position] == 0x2D { position += 1 }
        let digitsStart = position
        guard skipDigits() > 0 else { throw fail("Unexpected text") }
        if bytes[digitsStart] == 0x30, position - digitsStart > 1 { throw fail("Leading zero") }
        if position < bytes.count, bytes[position] == 0x2E {
            isInteger = false
            position += 1
            guard skipDigits() > 0 else { throw fail("Bad number") }
        }
        if position < bytes.count, bytes[position] == 0x65 || bytes[position] == 0x45 {
            isInteger = false
            position += 1
            if position < bytes.count, bytes[position] == 0x2B || bytes[position] == 0x2D { position += 1 }
            guard skipDigits() > 0 else { throw fail("Bad number") }
        }
        let text = String(bytes: bytes[start..<position], encoding: .utf8) ?? ""
        if isInteger, let value = Int(text) { return .int(value) }
        guard let value = Double(text), value.isFinite else { throw fail("Bad number") }
        return .number(value)
    }
}
