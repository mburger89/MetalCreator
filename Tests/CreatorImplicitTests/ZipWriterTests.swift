import Foundation
import Testing
@testable import CreatorImplicit

/// Our own zip writer and reader (implicit spec §5.3): valid, checked by CRC, the same bytes every time.
struct ZipWriterTests {
    func temporary(_ name: String = "zip") -> URL {
        URL.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString).zip")
    }

    @Test func theCRCOfTheStandardCheckStringIsTheStandardValue() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum([UInt8]()) == 0)
        let parts = CRC32.update(CRC32.update(0, Array("1234".utf8)), Array("56789".utf8))
        #expect(parts == 0xCBF4_3926, "in pieces gives the same")
    }

    @Test(arguments: [ZipWriter.Method.stored, ZipWriter.defaultMethod])
    func entriesReadBackWithTheirNamesAndContent(_ method: ZipWriter.Method) throws {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        var zip = try ZipWriter(destination: url)
        try zip.beginEntry("a.txt", method: method)
        try zip.write(Array("hello, ".utf8))
        try zip.write(Array("world".utf8))
        try zip.endEntry()
        try zip.beginEntry("dir/b.bin", method: method)
        let bytes = (0..<5_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        try zip.write(bytes)
        try zip.endEntry()
        try zip.beginEntry("empty", method: method)
        try zip.endEntry()
        try zip.finish()
        let reader = try ZipReader(contentsOf: url)
        #expect(reader.entries.map(\.name) == ["a.txt", "dir/b.bin", "empty"])
        #expect(String(bytes: try reader.contents(of: "a.txt"), encoding: .utf8) == "hello, world")
        let (binary, empty) = (try reader.contents(of: "dir/b.bin"), try reader.contents(of: "empty"))
        #expect(Array(binary) == bytes && empty.isEmpty)
        #expect(reader.entries.allSatisfy { $0.method == method.rawValue })
        #expect(throws: ZipError.missingEntry("nope")) { try reader.contents(of: "nope") }
    }

    @Test func aRepetitiveEntryIsSmallerDeflatedThanStoredWhereDeflateExists() throws {
        let text = Array(String(repeating: "<vertex x=\"1.5\" y=\"2\" z=\"0\"/>\n", count: 5_000).utf8)
        var sizes: [ZipWriter.Method: Int] = [:]
        for method in [ZipWriter.Method.stored, ZipWriter.defaultMethod] {
            let url = temporary()
            defer { try? FileManager.default.removeItem(at: url) }
            var zip = try ZipWriter(destination: url)
            try zip.beginEntry("m", method: method)
            try zip.write(text)
            try zip.endEntry()
            try zip.finish()
            sizes[method] = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }
        if ZipWriter.defaultMethod == .deflated {
            #expect((sizes[.deflated] ?? .max) < (sizes[.stored] ?? 0) / 10)
        } else {
            #expect(sizes[.stored] != nil && sizes.count == 1, "stored is all there is")
        }
    }

    @Test func theSameEntriesGiveTheSameBytes() throws {
        var files: [Data] = []
        for _ in 0..<2 {
            let url = temporary()
            defer { try? FileManager.default.removeItem(at: url) }
            var zip = try ZipWriter(destination: url)
            try zip.beginEntry("x")
            try zip.write(Array("same".utf8))
            try zip.endEntry()
            try zip.finish()
            files.append(try Data(contentsOf: url))
        }
        #expect(files[0] == files[1])
    }

    @Test func aDamagedEntryFailsItsChecksum() throws {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        var zip = try ZipWriter(destination: url)
        try zip.beginEntry("x", method: .stored)
        try zip.write(Array("untouched".utf8))
        try zip.endEntry()
        try zip.finish()
        var data = try Data(contentsOf: url)
        data[data.startIndex + 31 + 3] ^= 0xFF  // a byte of the content, after the 30-byte header and the 1-byte name
        try data.write(to: url)
        #expect(throws: ZipError.checksumMismatch("x")) { try ZipReader(contentsOf: url).contents(of: "x") }
    }

    /// Writes `entries` (name, content) with Zip64 forced at `threshold` and reads the file back with our reader.
    func roundTrip(_ entries: [(String, [UInt8])], method: ZipWriter.Method, zip64At threshold: UInt64) throws -> (URL, ZipReader) {
        let url = temporary("zip64")
        var zip = try ZipWriter(destination: url, zip64At: threshold)
        for (name, content) in entries {
            try zip.beginEntry(name, method: method)
            try zip.write(content)
            try zip.endEntry()
        }
        try zip.finish()
        return (url, try ZipReader(contentsOf: url))
    }

    @Test(arguments: [ZipWriter.Method.stored, ZipWriter.defaultMethod])
    func anEntryAndAnOffsetPastTheZip64LimitAreWrittenInFullAndReadBack(_ method: ZipWriter.Method) throws {
        // A limit of 100 bytes makes the sizes of "big", the offset of "after" and the directory's own offset need Zip64.
        let big = (0..<400).map { UInt8(truncatingIfNeeded: $0 &* 13) }
        let (url, reader) = try roundTrip([("small", [1, 2, 3]), ("big", big), ("after", Array("tail".utf8))], method: method, zip64At: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(reader.entries.map(\.name) == ["small", "big", "after"])
        #expect(reader.entries.map(\.size) == [3, 400, 4])
        let bigBack = try reader.contents(of: "big"), afterBack = try reader.contents(of: "after")
        let smallBack = try reader.contents(of: "small")
        #expect(Array(bigBack) == big && Array(afterBack) == Array("tail".utf8) && Array(smallBack) == [1, 2, 3])
        let listed = try ZipReader.listing(of: url)
        #expect(listed.map(\.name) == ["small", "big", "after"] && listed.map(\.offset) == reader.entries.map(\.offset))
    }

    @Test func aSmallFileIsPlainZipWithNoZip64Records() throws {
        let (url, _) = try roundTrip([("a", Array("hello".utf8))], method: .stored, zip64At: 0xFFFF_FFFF)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let signature = Data([0x50, 0x4B, 0x06, 0x06])  // the Zip64 end-of-directory record
        #expect(data.range(of: signature) == nil)
        #expect(data.range(of: Data([0x50, 0x4B, 0x07, 0x08])) != nil, "the 16-byte data descriptor of a small entry")
    }

    @Test func aZip64FileHasItsEndRecordsAndAnExtraFieldForEachOverflow() throws {
        let (url, _) = try roundTrip([("big", [UInt8](repeating: 7, count: 300))], method: .stored, zip64At: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Array(try Data(contentsOf: url))
        func find(_ signature: [UInt8]) -> Int? {
            (0...(data.count - signature.count)).first { Array(data[$0..<($0 + signature.count)]) == signature }
        }
        #expect(find([0x50, 0x4B, 0x06, 0x06]) != nil && find([0x50, 0x4B, 0x06, 0x07]) != nil)
        #expect(find([0x01, 0x00, 0x10, 0x00]) != nil, "the extra field 0x0001 with two 8-byte sizes (the offset is 0, so not wide)")
    }

    @Test func aWideEntryHasAn8ByteDescriptor() throws {
        let (url, _) = try roundTrip([("big", [UInt8](repeating: 7, count: 300))], method: .stored, zip64At: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Array(try Data(contentsOf: url))
        let at = try #require((0...(data.count - 4)).first { Array(data[$0..<($0 + 4)]) == [0x50, 0x4B, 0x07, 0x08] })
        func u64(_ from: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(data[from + $1]) << UInt64(8 * $1) } }
        #expect(u64(at + 8) == 300 && u64(at + 16) == 300, "compressed and uncompressed size as u64")
        #expect(Array(data[(at + 24)..<(at + 28)]) == [0x50, 0x4B, 0x01, 0x02], "the central directory follows the 24-byte descriptor")
    }

    /// The installed independent readers with the arguments that precede the file.
    static let independentReaders: [(path: String, leading: [String])] = [
        ("/opt/homebrew/bin/python3", ["-I", "-m", "zipfile", "-t"]), ("/usr/bin/unzip", ["-t"])
    ].filter { FileManager.default.isExecutableFile(atPath: $0.0) }

    /// An independent reader (Python's zipfile, then unzip) checks the Zip64 layout; skipped where neither is installed.
    @Test(.enabled(if: ZipWriterTests.independentReaders.isEmpty == false, "no independent zip reader installed"),
          arguments: [ZipWriter.Method.stored, ZipWriter.defaultMethod])
    func anIndependentReaderAcceptsAZip64File(_ method: ZipWriter.Method) throws {
        let big = (0..<400).map { UInt8(truncatingIfNeeded: $0 &* 13) }
        let (url, _) = try roundTrip([("small", [1, 2, 3]), ("big", big), ("after", Array("tail".utf8))], method: method, zip64At: 100)
        defer { try? FileManager.default.removeItem(at: url) }
        for (path, leading) in Self.independentReaders {
            let process = Process()
            process.executableURL = URL(filePath: path)
            process.arguments = leading + [url.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(path) \(leading.joined(separator: " "))")
        }
    }

    @Test func manyEntriesPastSixtyFiveThousandAreCountedInZip64() throws {
        // The count field is 16 bits; the end record says so with all ones and the Zip64 record has the number.
        let url = temporary("many")
        defer { try? FileManager.default.removeItem(at: url) }
        var zip = try ZipWriter(destination: url)
        for index in 0..<65_540 {
            try zip.beginEntry("e\(index)", method: .stored)
            try zip.endEntry()
        }
        try zip.finish()
        let reader = try ZipReader(contentsOf: url)
        #expect(reader.entries.count == 65_540 && reader.entries.last?.name == "e65539")
    }

    @Test func aMisusedWriterThrowsInsteadOfCrashing() throws {
        let url = temporary()
        var zip = try ZipWriter(destination: url)
        #expect(throws: ZipError.misuse("no entry is open")) { try zip.write([1]) }
        #expect(throws: ZipError.misuse("no entry is open")) { try zip.endEntry() }
        try zip.beginEntry("x", method: .stored)
        #expect(throws: ZipError.misuse("the last entry is still open")) { try zip.beginEntry("y") }
        #expect(throws: ZipError.misuse("the last entry is still open")) { try zip.finish() }
        zip.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!ZipError.misuse("x").userMessage.isEmpty)
    }

    @Test func aCancelledZipLeavesNoFile() throws {
        let url = temporary()
        var zip = try ZipWriter(destination: url)
        try zip.beginEntry("x")
        try zip.write(Array("half".utf8))
        zip.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func notAZipIsSaidSo() throws {
        let url = temporary("not")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("plain text, not a zip at all, but long enough to hold a record".utf8).write(to: url)
        #expect(throws: ZipError.notAZip) { try ZipReader(contentsOf: url) }
    }
}
