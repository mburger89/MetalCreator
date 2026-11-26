import CreatorGeometry
import Foundation
import Testing

/// DR-5 R23: a bounded read of a file somebody else put there, in a temporary folder.
struct RegularFileTests {
    static func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "RegularFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aSmallFileIsRead() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.bin")
        try Data([1, 2, 3]).write(to: file)
        #expect(try RegularFile.read(file, limit: 10) == Data([1, 2, 3]))
    }

    @Test func aFileAtTheLimitIsRead() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.bin")
        let bytes = Data(repeating: 7, count: 64)
        try bytes.write(to: file)
        #expect(try RegularFile.read(file, limit: 64) == bytes)
        #expect(throws: RegularFileProblem.tooLarge(size: 64)) { try RegularFile.read(file, limit: 63) }
    }

    @Test func aLargerFileIsRefusedFromItsSize() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "big.bin")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()
        #expect(throws: RegularFileProblem.tooLarge(size: 1_073_741_824)) { try RegularFile.read(file, limit: 3_145_728) }
    }

    @Test func aFolderIsNotAFile() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: RegularFileProblem.notAFile) { try RegularFile.read(folder, limit: 10) }
    }

    #if !os(Windows)
    @Test func aFIFOIsNotAFile() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pipe = folder.appending(path: "pipe")
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o600) == 0)
        #expect(throws: RegularFileProblem.notAFile) { try RegularFile.read(pipe, limit: 10) }
    }
    #endif

    @Test func aMissingFileIsUnreadable() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let problem = #expect(throws: RegularFileProblem.self) { try RegularFile.read(folder.appending(path: "nope"), limit: 10) }
        guard case .unreadable(let reason)? = problem else {
            Issue.record("expected .unreadable, got \(String(describing: problem))")
            return
        }
        #expect(!reason.isEmpty && reason.hasSuffix("."))
    }
}
