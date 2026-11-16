import Foundation

/// Reads a KiCad S-expression from bytes: one scanner over the `Data`, an explicit stack (no recursion), limits checked before
/// anything is appended, cancellation asked every `cancelEvery` tokens.
public enum SExpressionReader {
    public static func read(_ data: Data, limits: KiCadLimits = .standard,
                            isCancelled: () -> Bool = { false }) throws -> SExpression {
        guard data.count <= limits.maxFileBytes else {
            throw KiCadProblem("This board file is larger than \(limits.maxFileBytes >> 20) MB.")
        }
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
            let byte = bytes[position]
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

    private static func text(_ bytes: some Sequence<UInt8>) -> String {
        String(bytes: bytes, encoding: .utf8) ?? "\u{FFFD}"
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

    private static func barred(_ bytes: [UInt8], _ position: inout Int, _ limits: KiCadLimits) throws -> String {
        position += 1
        let start = position
        while position < bytes.count, bytes[position] != UInt8(ascii: "|") {
            position += 1
            if position - start > limits.maxStringBytes { throw tooLong(limits) }
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
