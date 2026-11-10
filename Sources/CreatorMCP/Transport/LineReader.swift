import Foundation

/// Splits a byte stream into lines on "\n", stripping a trailing "\r". A line longer than 16 MiB is reported once as `.tooLong`
/// and the reader stops yielding, because the connection is closed after it.
struct LineReader {
    enum Line: Equatable {
        case line(Data)
        case tooLong
    }

    static let maximumLineLength = 16 * 1_048_576

    private var buffer: [UInt8] = []
    private var start = 0
    private var scanned = 0
    private var failed = false

    mutating func append(_ bytes: ArraySlice<UInt8>) {
        guard !failed else { return }
        buffer.append(contentsOf: bytes)
    }

    /// The next complete line, or `nil` when more bytes are needed.
    mutating func nextLine() -> Line? {
        guard !failed else { return nil }
        let from = max(start, scanned)
        let newline = buffer[from...].firstIndex(of: 0x0A)
        let end = newline ?? buffer.count
        guard end - start <= Self.maximumLineLength else { return fail() }
        guard let newline else {
            scanned = buffer.count
            return nil
        }
        var lineEnd = newline
        if lineEnd > start, buffer[lineEnd - 1] == 0x0D { lineEnd -= 1 }
        let line = Data(buffer[start..<lineEnd])
        start = newline + 1
        scanned = start
        if start > 1_048_576, start * 2 > buffer.count {
            buffer.removeFirst(start)
            scanned -= start
            start = 0
        }
        return .line(line)
    }

    private mutating func fail() -> Line {
        failed = true
        buffer = []
        start = 0
        scanned = 0
        return .tooLong
    }
}
