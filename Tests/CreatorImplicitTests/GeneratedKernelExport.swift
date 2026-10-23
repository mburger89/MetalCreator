import Foundation
import Testing
@testable import CreatorImplicit

/// Writes `GeneratedKernels.sources` to `.build/generated-kernels/source` (only with `XP_EXPORT_KERNELS=1`: `scripts/linux-test.sh kernels` runs
/// it), each `<digest>.comp.hlsl`. A file that exists with the same name is the same text (the name is its digest) and is left alone.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["XP_EXPORT_KERNELS"] == "1", "set XP_EXPORT_KERNELS=1"))
struct GeneratedKernelExport {
    @Test func exportEveryKernelSource() throws {
        try FileManager.default.createDirectory(at: GeneratedKernels.source, withIntermediateDirectories: true)
        for source in GeneratedKernels.sources {
            let file = GeneratedKernels.source.appending(path: "\(source.digest).comp.hlsl")
            if !FileManager.default.fileExists(atPath: file.path) { try Data(source.text.utf8).write(to: file) }
        }
    }
}
