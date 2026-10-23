#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// `--self-test`'s "implicit compiler" line (plan xp-c task 12): MetalUI's `SDLGPUShaderCompiler.selfTest(for:)`, which loads the library, compiles a
/// kernel and a broken one (DXC's diagnostics required), and with a device dispatches it and reads it back; without a device (a clean container) the
/// SPIR-V route alone. It throws `compilerUnavailable`, listing the paths tried, in a package without the libraries.
enum SDLCompilerSelfTest {
    static func run() async throws -> String {
        let report = try await SDLGPUShaderCompiler.selfTest(for: SDLGPUDevice.make())
        let seconds = report.seconds.formatted(.number.precision(.fractionLength(2)))
        return "\(report.libraryPath), \(report.format) on \(report.driver), \(report.compiledBytes.formatted()) bytes in \(seconds) s"
    }
}
#endif
