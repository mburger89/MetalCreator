import Foundation

/// Reads a zip, ours or another tool's (Zip64 included): the central directory, then each entry checked against its CRC. The file is
/// untrusted: every offset and size is checked, nothing traps, and an entry's declared size is held to a limit before anything is allocated.
/// It holds the whole file; a Zip64 file of gigabytes is listed by `ZipReader.listing(of:)`, which reads the end of the file alone.
public struct ZipReader {
    public struct Entry: Sendable {
        public var name: String
        public var method: UInt16
        public var crc: UInt32
        public var compressedSize: Int
        public var size: Int
        public var offset: Int
        /// The general purpose bit flag (bit 0: encrypted).
        public var flags: UInt16 = 0
    }

    public let entries: [Entry]
    private let data: Data

    /// The most an entry may declare when asked for by name alone.
    public static let defaultLimit = 1 << 31

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// Reads the zip held in `data`. Throws when the directory is damaged or two entries' bytes overlap.
    public init(data: Data) throws {
        let data = Data(data)  // indices from zero
        let found = try Self.directory(of: data)
        var spans: [(start: Int, end: Int)] = []
        for entry in found {
            let start = try Self.dataStart(of: entry, in: data)
            spans.append((entry.offset, start + entry.compressedSize))
        }
        spans.sort { $0.start < $1.start }
        for (previous, next) in zip(spans, spans.dropFirst()) where next.start < previous.end { throw ZipError.overlappingEntries }
        self.data = data
        entries = found
    }

    /// The entries of a zip, read from its end alone: the last megabyte holds the central directory of any zip this app writes, so a file
    /// of gigabytes is listed without being read.
    public static func listing(of url: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        let tail = min(length, 1 << 20)
        try handle.seek(toOffset: length - tail)
        let data = try handle.read(upToCount: Int(tail)) ?? Data()
        return try directory(of: data, offsetOfData: Int(length - tail))
    }

    /// Parses the end records and the central directory of `data`, a whole file or the tail of one that starts at `offsetOfData`.
    private static func directory(of data: Data, offsetOfData: Int = 0) throws -> [Entry] {
        guard data.count >= 22, let end = endOfDirectory(in: data) else { throw ZipError.notAZip }
        var (count, size, position) = (Int(u16(data, end + 10)), Int(u32(data, end + 12)), Int(u32(data, end + 16)))
        // All ones in a field of the end record say the numbers are in the Zip64 end record, found by the locator just before.
        let wide = count == 0xFFFF || position == 0xFFFF_FFFF || size == 0xFFFF_FFFF
        if wide, end >= 20, u32(data, end - 20) == 0x0706_4B50 {
            let located = try int(u64(data, end - 20 + 8))
            let (record, overflow) = located.subtractingReportingOverflow(offsetOfData)
            guard !overflow, record >= 0, record <= data.count - 56, u32(data, record) == 0x0606_4B50 else { throw ZipError.notAZip }
            count = try int(u64(data, record + 32))
            size = try int(u64(data, record + 40))
            position = try int(u64(data, record + 48))
        }
        let (start, overflow) = position.subtractingReportingOverflow(offsetOfData)
        guard !overflow, start >= 0, size >= 0, start <= data.count, size <= data.count - start else { throw ZipError.notAZip }
        // A record is at least 46 bytes, so a count the directory cannot hold is a lie.
        guard count >= 0, count <= size / 46 else { throw ZipError.notAZip }
        position = start
        let limit = start + size
        var found: [Entry] = []
        for _ in 0..<count {
            let (entry, length) = try record(at: position, in: data)
            found.append(entry)
            let (next, over) = position.addingReportingOverflow(length)
            guard !over, next <= limit else { throw ZipError.notAZip }
            position = next
        }
        return found
    }

    /// The central directory record at `position`, and its length.
    private static func record(at position: Int, in data: Data) throws -> (Entry, Int) {
        guard position >= 0, position <= data.count - 46, u32(data, position) == 0x0201_4B50 else { throw ZipError.notAZip }
        let nameLength = Int(u16(data, position + 28)), extraLength = Int(u16(data, position + 30))
        let comment = Int(u16(data, position + 32))
        guard position + 46 + nameLength + extraLength <= data.count else { throw ZipError.notAZip }
        let name = String(bytes: data[(data.startIndex + position + 46)..<(data.startIndex + position + 46 + nameLength)],
                          encoding: .utf8) ?? ""
        var entry = Entry(name: name, method: u16(data, position + 10), crc: u32(data, position + 16),
                          compressedSize: Int(u32(data, position + 20)), size: Int(u32(data, position + 24)),
                          offset: Int(u32(data, position + 42)), flags: u16(data, position + 8))
        // The Zip64 extra holds, in this order, the fields that were all ones: size, compressed size, offset.
        var field = position + 46 + nameLength
        let extraEnd = field + extraLength
        while field + 4 <= extraEnd {
            let (id, length) = (u16(data, field), Int(u16(data, field + 2)))
            if id == 0x0001 {
                var at = field + 4
                for keyPath in [\Entry.size, \Entry.compressedSize, \Entry.offset] where entry[keyPath: keyPath] == 0xFFFF_FFFF {
                    guard at + 8 <= extraEnd else { throw ZipError.notAZip }
                    entry[keyPath: keyPath] = try int(u64(data, at))
                    at += 8
                }
            }
            field += 4 + length
        }
        return (entry, 46 + nameLength + extraLength + comment)
    }

    /// Where `entry`'s bytes start, from its local header (whose own sizes are not trusted: a data descriptor leaves them zero), checked to
    /// lie inside the file.
    private static func dataStart(of entry: Entry, in data: Data) throws -> Int {
        guard entry.offset >= 0, entry.offset <= data.count - 30, u32(data, entry.offset) == 0x0403_4B50 else { throw ZipError.notAZip }
        let header = 30 + Int(u16(data, entry.offset + 26)) + Int(u16(data, entry.offset + 28))
        let (start, overflow) = entry.offset.addingReportingOverflow(header)
        guard !overflow, start <= data.count, entry.compressedSize >= 0, entry.compressedSize <= data.count - start else {
            throw ZipError.notAZip
        }
        return start
    }

    private static func int(_ value: UInt64) throws -> Int {
        guard let exact = Int(exactly: value) else { throw ZipError.notAZip }
        return exact
    }

    /// The content of `name`, inflated and checked against its CRC.
    public func contents(of name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.missingEntry(name) }
        return try content(of: entry, limit: Self.defaultLimit, isCancelled: { false })
    }

    /// The content of `entry`, inflated and checked against its CRC. An entry that declares more than `limit` bytes is refused before
    /// anything is allocated.
    /// - Throws: `ZipError`, or `CancellationError` when `isCancelled` answers true.
    public func content(of entry: Entry, limit: Int, isCancelled: () -> Bool = { false }) throws -> Data {
        guard entry.flags & 1 == 0 else { throw ZipError.encrypted(entry.name) }
        guard entry.size >= 0, entry.size <= min(limit, Self.defaultLimit) else { throw ZipError.tooLarge(entry.name) }
        let start = try Self.dataStart(of: entry, in: data)
        try Self.checkRatio(of: entry)
        let stored = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressedSize)]
        let content: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.size else { throw ZipError.checksumMismatch(entry.name) }
            content = Data(stored)
        case 8:
            do {
                content = try stored.withUnsafeBytes { try Inflate.inflate($0, size: entry.size, isCancelled: isCancelled) }
            } catch InflateError.cancelled {
                throw CancellationError()
            } catch {
                throw Self.zipError(for: error, in: entry)
            }
        default:
            throw ZipError.unsupportedMethod(entry.name)
        }
        guard content.count == entry.size, CRC32.checksum(content) == entry.crc else { throw ZipError.checksumMismatch(entry.name) }
        return content
    }

    /// What a failed inflate is to the zip's reader: an allocation that failed is the computer's, anything else a damaged entry.
    static func zipError(for error: any Error, in entry: Entry) -> ZipError {
        if let inflate = error as? InflateError, inflate == .allocationFailed { return .allocationFailed(entry.name) }
        return .checksumMismatch(entry.name)
    }

    /// A deflate stream cannot expand past about 1032:1 (a run of 258 bytes costs a quarter of a bit), so one that declares more than that
    /// from the bytes it holds is lying. Refused before the declared size is allocated.
    private static func checkRatio(of entry: Entry) throws {
        guard entry.method == 8 else { return }
        let (product, overflow) = entry.compressedSize.multipliedReportingOverflow(by: 1032)
        guard !overflow, entry.size <= product + 1024 else { throw ZipError.tooLarge(entry.name) }
    }

    /// The end record: the last signature whose comment length runs exactly to the end of the file (a signature inside a comment does not).
    private static func endOfDirectory(in data: Data) -> Int? {
        var position = data.count - 22
        let lowest = max(0, data.count - 22 - 65_535)
        while position >= lowest {
            if u32(data, position) == 0x0605_4B50, position + 22 + Int(u16(data, position + 20)) == data.count { return position }
            position -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ at: Int) -> UInt16 {
        UInt16(data[data.startIndex + at]) | UInt16(data[data.startIndex + at + 1]) << 8
    }

    private static func u32(_ data: Data, _ at: Int) -> UInt32 {
        UInt32(u16(data, at)) | UInt32(u16(data, at + 2)) << 16
    }

    private static func u64(_ data: Data, _ at: Int) -> UInt64 {
        UInt64(u32(data, at)) | UInt64(u32(data, at + 4)) << 32
    }
}
