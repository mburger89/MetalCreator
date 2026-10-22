import Foundation
import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

/// The shim writes STEP and STL to the path it is handed as UTF-8 (`URL.withUnsafeFileSystemRepresentation`). OpenCascade opens
/// it as UTF-8 on Linux and macOS; on Windows an old build opened it as the ANSI code page, and a name with an accent or a
/// letter outside it failed (xp-2; CI is the only place that runs this on Windows).
struct ExportPathTests {
    @Test(arguments: ExportFormat.allCases)
    func aFileNamedWithSpacesAccentsAndKanjiIsWritten(_ format: ExportFormat) async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let folder = URL.temporaryDirectory.appending(path: "Teile Größe \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Halterung ü 日本.\(format.rawValue)")
        try await kernel.export([solid], format: format, to: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 0, "\(url.lastPathComponent) is empty or missing")
    }
}
