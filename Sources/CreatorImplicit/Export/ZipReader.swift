import Foundation
#if canImport(Compression)
import Compression
#endif

/// Reads a zip written by `ZipWriter` (Zip64 included): the central directory, then each entry checked against its CRC. The tests read a
/// 3MF back with it; the app does not need to read zips. It holds the whole file, so it is for small files; a Zip64 file of gigabytes is
/// listed by `ZipReader.listing(of:)`, which reads the end of the file alone.
public struct ZipReader {
    public struct Entry: Sendable {
        public var name: String
        public var method: UInt16
        public var crc: UInt32
        public var compressedSize: Int
        public var size: Int
        public var offset: Int
    }

    public let entries: [Entry]
    private let data: Data

    public init(contentsOf url: URL) throws {
        data = try Data(contentsOf: url)
        entries = try Self.directory(of: data)
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
            let record = Int(u64(data, end - 20 + 8)) - offsetOfData
            guard record >= 0, record + 56 <= data.count, u32(data, record) == 0x0606_4B50 else { throw ZipError.notAZip }
            count = Int(u64(data, record + 32))
            size = Int(u64(data, record + 40))
            position = Int(u64(data, record + 48))
        }
        position -= offsetOfData
        guard position >= 0, size >= 0 else { throw ZipError.notAZip }
        var found: [Entry] = []
        for _ in 0..<count {
            let (entry, length) = try record(at: position, in: data)
            found.append(entry)
            position += length
        }
        return found
    }

    /// The central directory record at `position`, and its length.
    private static func record(at position: Int, in data: Data) throws -> (Entry, Int) {
        guard position + 46 <= data.count, u32(data, position) == 0x0201_4B50 else { throw ZipError.notAZip }
        let nameLength = Int(u16(data, position + 28)), extraLength = Int(u16(data, position + 30))
        let comment = Int(u16(data, position + 32))
        guard position + 46 + nameLength + extraLength <= data.count else { throw ZipError.notAZip }
        let name = String(bytes: data[(position + 46)..<(position + 46 + nameLength)], encoding: .utf8) ?? ""
        var entry = Entry(name: name, method: u16(data, position + 10), crc: u32(data, position + 16),
                          compressedSize: Int(u32(data, position + 20)), size: Int(u32(data, position + 24)),
                          offset: Int(u32(data, position + 42)))
        // The Zip64 extra holds, in this order, the fields that were all ones: size, compressed size, offset.
        var field = position + 46 + nameLength
        let extraEnd = field + extraLength
        while field + 4 <= extraEnd {
            let (id, length) = (u16(data, field), Int(u16(data, field + 2)))
            if id == 0x0001 {
                var at = field + 4
                for keyPath in [\Entry.size, \Entry.compressedSize, \Entry.offset] where entry[keyPath: keyPath] == 0xFFFF_FFFF {
                    guard at + 8 <= extraEnd else { throw ZipError.notAZip }
                    entry[keyPath: keyPath] = Int(u64(data, at))
                    at += 8
                }
            }
            field += 4 + length
        }
        return (entry, 46 + nameLength + extraLength + comment)
    }

    /// The content of `name`, inflated and checked against its CRC.
    public func contents(of name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.missingEntry(name) }
        let nameLength = Int(Self.u16(data, entry.offset + 26)), extra = Int(Self.u16(data, entry.offset + 28))
        let start = entry.offset + 30 + nameLength + extra
        guard start + entry.compressedSize <= data.count else { throw ZipError.notAZip }
        let stored = data[start..<(start + entry.compressedSize)]
        let content: Data
        switch entry.method {
        case 0:
            content = Data(stored)
        case 8:
            content = try Self.inflate(stored, size: entry.size, name: name)
        default:
            throw ZipError.unsupportedMethod(name)
        }
        guard content.count == entry.size, CRC32.checksum(content) == entry.crc else { throw ZipError.checksumMismatch(name) }
        return content
    }

    private static func inflate(_ compressed: Data.SubSequence, size: Int, name: String) throws -> Data {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            compressed.withUnsafeBytes { source -> Int in
                guard let to = destination.bindMemory(to: UInt8.self).baseAddress,
                      let from = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(to, size, from, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.checksumMismatch(name) }
        return output
        #else
        throw ZipError.unsupportedMethod(name)
        #endif
    }

    private static func endOfDirectory(in data: Data) -> Int? {
        var position = data.count - 22
        let lowest = max(0, data.count - 22 - 65_535)
        while position >= lowest {
            if u32(data, position) == 0x0605_4B50 { return position }
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
