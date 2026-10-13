// Test fixture file: a self-removing folder under the temporary directory, for the node tests that link to real files.
import Foundation

final class TempFolderForNodes {
    let url: URL

    init() {
        url = URL.temporaryDirectory.appending(path: "mc-nodes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes `data` at `name` (a path under the folder, its folders made) and returns the file's URL.
    @discardableResult
    func write(_ data: Data, to name: String) throws -> URL {
        let file = url.appending(path: name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    /// Sets a file's modification date.
    func touch(_ file: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
    }
}
