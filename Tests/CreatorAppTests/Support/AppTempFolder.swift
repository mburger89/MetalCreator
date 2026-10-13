// Test fixture file: a folder that removes itself, for the files an app test links to.
import Foundation

/// A folder that removes itself, for the files an app test links to.
final class AppTempFolder {
    let url = URL.temporaryDirectory.appending(path: "mc-app-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ data: Data, to name: String) throws -> URL {
        let file = url.appending(path: name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }
}
