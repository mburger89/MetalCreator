import Foundation
import Testing
@testable import CreatorImplicit

/// The zip reader on zips other tools wrote, and on hostile ones.
@Suite("ZipReaderForeign")
struct ZipReaderForeignTests {
    /// Python's `zipfile` writing to an unseekable stream: one deflated entry "a.txt" (`"hello zip "` fifty times), a data descriptor, and
    /// zeros in the local header's sizes.
    static let foreign: [UInt8] = [
        0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x08, 0x00, 0x08, 0x00, 0x00, 0x00, 0x21, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x61, 0x2E, 0x74, 0x78, 0x74, 0xCB,
        0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xA8, 0xCA, 0x2C, 0x50, 0xC8, 0x18, 0x65, 0x8D, 0x10, 0x16, 0x00, 0x50, 0x4B,
        0x07, 0x08, 0x77, 0x42, 0x4D, 0xD3, 0x11, 0x00, 0x00, 0x00, 0xF4, 0x01, 0x00, 0x00, 0x50, 0x4B, 0x01, 0x02,
        0x14, 0x03, 0x14, 0x00, 0x08, 0x00, 0x08, 0x00, 0x00, 0x00, 0x21, 0x00, 0x77, 0x42, 0x4D, 0xD3, 0x11, 0x00,
        0x00, 0x00, 0xF4, 0x01, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x80, 0x01, 0x00, 0x00, 0x00, 0x00, 0x61, 0x2E, 0x74, 0x78, 0x74, 0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x33, 0x00, 0x00, 0x00, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    static let text = Data(String(repeating: "hello zip ", count: 50).utf8)

    @Test func aForeignZipReads() throws {
        let zip = try ZipReader(data: Data(Self.foreign))
        #expect(zip.entries.map(\.name) == ["a.txt"])
        #expect(try zip.contents(of: "a.txt") == Self.text)
        let entry = try #require(zip.entries.first)
        #expect(try zip.content(of: entry, limit: 500, isCancelled: { false }) == Self.text)
    }

    @Test func aDeclaredSizeOverTheLimitIsRefusedBeforeAllocating() throws {
        let zip = try ZipReader(data: Data(Self.foreign))
        let entry = try #require(zip.entries.first)
        #expect(throws: ZipError.tooLarge("a.txt")) { try zip.content(of: entry, limit: 499, isCancelled: { false }) }
        // A claim of 4 GB (Zip64) on a few bytes is refused by the 2 GB ceiling, whatever the caller's limit.
        var huge = entry
        huge.size = 1 << 32
        #expect(throws: ZipError.tooLarge("a.txt")) { try zip.content(of: huge, limit: .max, isCancelled: { false }) }
    }

    @Test func aZip64EntryReads() throws {
        let body = Data("zip64 body".utf8)
        let file = Self.build([Item(name: "big.bin", body: body)], zip64: true)
        let zip = try ZipReader(data: file)
        #expect(zip.entries.first?.size == body.count)
        #expect(try zip.contents(of: "big.bin") == body)
    }

    @Test func aBadCRCIsRefused() throws {
        var bytes = Self.foreign
        bytes[84] ^= 0xFF  // the CRC in the central directory record at 68, which is the one the reader trusts
        let zip = try ZipReader(data: Data(bytes))
        #expect(throws: ZipError.checksumMismatch("a.txt")) { try zip.contents(of: "a.txt") }
    }

    @Test func aCentralDirectoryPointingOutsideTheFileIsRefused() {
        var bytes = Self.foreign
        bytes[bytes.count - 6] = 0xF0  // the directory's offset, in the end record
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data(bytes)) }
        var local = Self.foreign
        local[68 + 42] = 0xFF  // the entry's local-header offset moves past the end
        local[68 + 43] = 0x7F
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data(local)) }
        // A local header whose own name length carries the data past the end.
        var name = Self.foreign
        name[26] = 0xFF
        name[27] = 0xFF
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data(name)) }
    }

    @Test func aDirectoryCountThatTheBytesCannotHoldIsRefused() {
        var bytes = Self.foreign
        bytes[bytes.count - 12] = 0xFE  // 254 entries claimed in a directory of one record
        bytes[bytes.count - 14] = 0xFE
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data(bytes)) }
    }

    @Test func aCommentAfterTheEndRecordIsRead() throws {
        var bytes = Self.foreign
        bytes[bytes.count - 2] = 4  // comment length
        bytes += Array("PK\u{5}\u{6}".utf8)  // a fake end signature inside the comment
        let zip = try ZipReader(data: Data(bytes))
        #expect(try zip.contents(of: "a.txt") == Self.text)
        var lying = Self.foreign
        lying[lying.count - 2] = 9  // longer than what follows
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data(lying)) }
    }

    @Test func overlappingEntriesAreRefused() {
        let items = [Item(name: "a", body: Data("one".utf8)), Item(name: "b", body: Data("two".utf8), offsetOverride: 0)]
        let file = Self.build(items, zip64: false)
        #expect(throws: ZipError.overlappingEntries) { try ZipReader(data: file) }
    }

    @Test func encryptedEntriesAreRefused() throws {
        let file = Self.build([Item(name: "a", body: Data("one".utf8), flags: 1)], zip64: false)
        let zip = try ZipReader(data: file)
        #expect(throws: ZipError.encrypted("a")) { try zip.contents(of: "a") }
    }

    @Test func cancellationIsReported() throws {
        let zip = try ZipReader(data: Data(Self.foreign))
        let entry = try #require(zip.entries.first)
        #expect(throws: CancellationError.self) { try zip.content(of: entry, limit: 500, isCancelled: { true }) }
    }

    // MARK: A small builder for stored entries

    struct Item {
        var name: String
        var body: Data
        var flags: UInt16 = 0
        var offsetOverride: Int?
    }

    static func build(_ items: [Item], zip64: Bool) -> Data {
        var out = Data(), directory = Data()
        for item in items {
            let offset = out.count
            let name = Data(item.name.utf8)
            let crc = CRC32.checksum(item.body)
            out += le(0x0403_4B50, 4) + le(20, 2) + le(UInt64(item.flags), 2) + le(0, 2) + le(0, 4) + le(UInt64(crc), 4)
            out += le(UInt64(item.body.count), 4) + le(UInt64(item.body.count), 4) + le(UInt64(name.count), 2) + le(0, 2) + name + item.body
            let size = le(UInt64(item.body.count), 8)
            let extra = zip64 ? le(1, 2) + le(24, 2) + size + size + le(UInt64(offset), 8) : Data()
            let wide: UInt64 = 0xFFFF_FFFF
            directory += le(0x0201_4B50, 4) + le(20, 2) + le(20, 2) + le(UInt64(item.flags), 2) + le(0, 2) + le(0, 4) + le(UInt64(crc), 4)
            directory += le(zip64 ? wide : UInt64(item.body.count), 4) + le(zip64 ? wide : UInt64(item.body.count), 4)
            directory += le(UInt64(name.count), 2) + le(UInt64(extra.count), 2) + le(0, 2) + le(0, 2) + le(0, 2) + le(0, 4)
            directory += le(zip64 ? wide : UInt64(item.offsetOverride ?? offset), 4) + name + extra
        }
        let start = out.count
        out += directory
        if zip64 {
            let record = out.count
            out += le(0x0606_4B50, 4) + le(44, 8) + le(45, 2) + le(45, 2) + le(0, 4) + le(0, 4)
            out += le(UInt64(items.count), 8) + le(UInt64(items.count), 8) + le(UInt64(directory.count), 8) + le(UInt64(start), 8)
            out += le(0x0706_4B50, 4) + le(0, 4) + le(UInt64(record), 8) + le(1, 4)
            out += le(0x0605_4B50, 4) + le(0, 4) + le(0xFFFF, 2) + le(0xFFFF, 2) + le(0xFFFF_FFFF, 4) + le(0xFFFF_FFFF, 4) + le(0, 2)
        } else {
            out += le(0x0605_4B50, 4) + le(0, 4) + le(UInt64(items.count), 2) + le(UInt64(items.count), 2)
            out += le(UInt64(directory.count), 4) + le(UInt64(start), 4) + le(0, 2)
        }
        return out
    }

    static func le(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) })
    }
}

extension ZipReaderForeignTests {
    /// A deflate stream cannot expand past about 1032:1, so a few bytes that claim a gigabyte are refused before anything is allocated.
    @Test func aDeflatedSizeBeyondWhatItsBytesCouldMakeIsRefused() throws {
        var bytes = Self.foreign
        // The central directory record is at 68; its uncompressed size is at 24 within it. 22 bytes cannot make a gigabyte.
        bytes[68 + 24 + 3] = 0x40
        let zip = try ZipReader(data: Data(bytes))
        let entry = try #require(zip.entries.first)
        #expect(entry.size > 1 << 29 && entry.compressedSize == 17)
        #expect(throws: ZipError.tooLarge("a.txt")) { try zip.content(of: entry, limit: .max, isCancelled: { false }) }
        // The honest size is still allowed.
        let honest = try ZipReader(data: Data(Self.foreign))
        #expect(try honest.contents(of: "a.txt") == Self.text)
    }
}
