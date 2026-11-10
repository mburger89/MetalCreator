import Foundation

/// An absolute path for `name` that is absolute on every platform ("/tmp/…" is relative on Windows, which wants a drive).
func absoluteTestPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent(name).path
}
