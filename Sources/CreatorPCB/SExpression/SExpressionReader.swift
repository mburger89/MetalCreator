import Foundation

/// Reads a KiCad S-expression from bytes: one scanner over the `Data`, an explicit stack (no recursion), limits checked before
/// anything is appended, cancellation asked every `cancelEvery` tokens.
public enum SExpressionReader {
    /// `skipping` names top-level children of the root that are scanned past without being built (limits and cancellation still apply).
    public static func read(_ data: Data, limits: KiCadLimits = .standard, skipping: Set<String> = [],
                            isCancelled: () -> Bool = { false }) throws -> SExpression {
        try requireSize(data, limits)
        let notBoard = KiCadProblem("This isn't a KiCad board file.")
        let bytes = [UInt8](data)
        var position = 0
        var stack: [[SExpression]] = []
        var root: SExpression?
        var tokens = 0
        while true {
            while position < bytes.count, isSpace(bytes[position]) { position += 1 }
            guard position < bytes.count else { break }
            tokens += 1
            if tokens % limits.cancelEvery == 0, isCancelled() { throw CancellationError() }
            if stack.count == 1, try skipsList(bytes, &position, skipping, limits, isCancelled) { continue }
            guard let value = try token(bytes, &position, &stack, limits, notBoard) else { continue }
            if stack.isEmpty {
                guard root == nil, case .list = value else { throw notBoard }
                root = value
            } else {
                stack[stack.count - 1].append(value)
            }
        }
        guard stack.isEmpty else { throw KiCadProblem("The board file is damaged: a list isn't closed.") }
        guard let root else { throw notBoard }
        return root
    }

    private static func requireSize(_ data: Data, _ limits: KiCadLimits) throws {
        guard data.count <= limits.maxFileBytes else {
            throw KiCadProblem("This board file is larger than \(limits.maxFileBytes >> 20) MB.")
        }
    }

    /// When the list opening at `position` (a child of the root) starts with a keyword in `skipping`, moves past its closing
    /// parenthesis and says true.
    private static func skipsList(_ bytes: [UInt8], _ position: inout Int, _ skipping: Set<String>,
                                  _ limits: KiCadLimits, _ isCancelled: () -> Bool) throws -> Bool {
        guard !skipping.isEmpty, bytes[position] == UInt8(ascii: "(") else { return false }
        var look = position + 1
        while look < bytes.count, isSpace(bytes[look]) { look += 1 }
        let start = look
        while look < bytes.count, look - start <= 64, !isDelimiter(bytes[look]) { look += 1 }
        guard look > start, look - start <= 64, skipping.contains(text(bytes[start..<look])) else { return false }
        try scanPast(bytes, &position, limits, isCancelled)
        return true
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        isSpace(byte) || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")") || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "|")
    }

    /// Moves past the list that opens at `position`, building nothing; its depth counts under the root's.
    private static func scanPast(_ bytes: [UInt8], _ position: inout Int, _ limits: KiCadLimits,
                                 _ isCancelled: () -> Bool) throws {
        var open = 0
        var scanned = 0
        while position < bytes.count {
            scanned += 1
            if scanned % limits.cancelEvery == 0, isCancelled() { throw CancellationError() }
            switch bytes[position] {
            case UInt8(ascii: "("):
                open += 1
                guard 1 + open <= limits.maxDepth else {
                    throw KiCadProblem("The board file is damaged: lists are nested more than \(limits.maxDepth) levels deep.")
                }
                position += 1
            case UInt8(ascii: ")"):
                open -= 1
                position += 1
                if open == 0 { return }
            case UInt8(ascii: "\""):
                _ = try quoted(bytes, &position, limits)
            case UInt8(ascii: "|") where isDelimiter(bytes[position - 1]):
                // A data block opens only at the start of a token, as in `token`; `/RX|TX` is one atom.
                _ = try barred(bytes, &position, limits)
            default:
                position += 1
            }
        }
        throw KiCadProblem("The board file is damaged: a list isn't closed.")
    }

    /// One token at `position`: a finished value, or nil when it opened a list.
    private static func token(_ bytes: [UInt8], _ position: inout Int, _ stack: inout [[SExpression]],
                              _ limits: KiCadLimits, _ notBoard: KiCadProblem) throws -> SExpression? {
        switch bytes[position] {
        case UInt8(ascii: "("):
            guard stack.count < limits.maxDepth else {
                throw KiCadProblem("The board file is damaged: lists are nested more than \(limits.maxDepth) levels deep.")
            }
            stack.append([])
            position += 1
            return nil
        case UInt8(ascii: ")"):
            guard let items = stack.popLast() else {
                throw KiCadProblem("The board file is damaged: a list is closed that was never opened.")
            }
            position += 1
            return .list(items)
        case UInt8(ascii: "\""):
            return .string(try quoted(bytes, &position, limits))
        case UInt8(ascii: "|"):
            return .string(try barred(bytes, &position, limits))
        default:
            return .atom(try atom(bytes, &position, limits, notBoard))
        }
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: bytes, as: UTF8.self) // lossy on purpose: a bad byte becomes U+FFFD, the rest stays
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }

    private static func tooLong(_ limits: KiCadLimits) -> KiCadProblem {
        KiCadProblem("The board file is damaged: it has a text longer than \(limits.maxStringBytes >> 20) MB.")
    }

    private static func quoted(_ bytes: [UInt8], _ position: inout Int, _ limits: KiCadLimits) throws -> String {
        position += 1
        var out: [UInt8] = []
        while position < bytes.count {
            var byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: "\"") { return text(out) }
            if byte == UInt8(ascii: "\\"), position < bytes.count {
                byte = bytes[position]
                position += 1
                if byte == UInt8(ascii: "n") { byte = 0x0A }
            }
            out.append(byte)
            if out.count > limits.maxStringBytes { throw tooLong(limits) }
        }
        throw KiCadProblem("The board file is damaged: a quoted text isn't closed.")
    }

    /// A `|…|` data token (an embedded file's base64) is bounded by the file size alone, not `maxStringBytes`.
    private static func barred(_ bytes: [UInt8], _ position: inout Int, _ limits: KiCadLimits) throws -> String {
        position += 1
        let start = position
        while position < bytes.count, bytes[position] != UInt8(ascii: "|") {
            position += 1
        }
        guard position < bytes.count else { throw KiCadProblem("The board file is damaged: a data block isn't closed.") }
        let text = text(bytes[start..<position])
        position += 1
        return text
    }

    private static func atom(_ bytes: [UInt8], _ position: inout Int, _ limits: KiCadLimits,
                             _ notBoard: KiCadProblem) throws -> String {
        let start = position
        while position < bytes.count {
            let byte = bytes[position]
            if isSpace(byte) || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")") || byte == UInt8(ascii: "\"") { break }
            if byte < 0x20 || byte == 0 { throw notBoard }
            position += 1
            if position - start > limits.maxStringBytes { throw tooLong(limits) }
        }
        return text(bytes[start..<position])
    }
}
