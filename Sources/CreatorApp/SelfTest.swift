import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUI
#if canImport(Metal)
import Metal
#elseif canImport(MetalUISDL)
import MetalUISDL
#endif

/// `MetalCreator --self-test` (docs/superpowers/specs/2026-10-09-packaging-design.md): proves, without opening a
/// window, that the app reaches everything it ships. The kernel check models, measures and meshes a cube on OCCT; the
/// exports write STEP and STL, which run OCCT's data-exchange libraries; the shader check finds MetalUI's shader
/// resource bundle and compiles it on the Metal device (off macOS it finds the SDL backend's compiled shader
/// directory). The packaging script runs it on the finished `.app` with Homebrew's directories unreadable.
@MainActor
public enum SelfTest {
    /// Runs every check in order. Exports are written into `scratch`, which is created and then removed.
    /// `compileShaders` is ``compileShaders()`` unless a test stands in for it.
    public static func run(kernel: any Kernel, scratch: URL,
                           compileShaders: @MainActor () throws -> Void = SelfTest.compileShaders) async -> SelfTestReport {
        var results: [SelfTestResult] = []
        var cube: Solid?
        results.append(await check("kernel") {
            let solid = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                 mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
            let volume = try await kernel.properties(of: solid).volume
            guard abs(volume - 1000) < 1e-6 else {
                throw Failure("a 10 mm cube measured \(volume.formatted()) mm³, not 1000 mm³.")
            }
            let triangles = try await kernel.tessellate(solid, tolerance: 0.1).indices.count / 3
            guard triangles > 0 else { throw Failure("the 10 mm cube meshed into no triangles.") }
            cube = solid
            return "a 10 mm cube, 1000 mm³, meshed into \(triangles) triangles"
        })
        // A kernel that says geometry isn't available (`KernelUnavailable`; the app itself has OpenCascade everywhere since xp-2) skips the checks that need one.
        let kernelSkipped = results[0].passed && results[0].detail.hasPrefix(Self.skippedPrefix)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            results.append(SelfTestResult(name: "scratch folder", passed: false, detail: describe(error)))
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        for format in ExportFormat.allCases {
            results.append(await check("\(format.rawValue.uppercased()) export") {
                guard let cube else {
                    throw kernelSkipped ? KernelError.unavailable : Failure("skipped: the kernel check made no cube.")
                }
                let url = scratch.appending(path: "self-test.\(format.rawValue)")
                try await kernel.export([cube], format: format, to: url)
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
                guard size > 0 else { throw Failure("the file is empty.") }
                return "\(size.formatted()) bytes"
            })
        }
        results.append(await check("shaders") {
            try compileShaders()
            return shadersDetail
        })
        return SelfTestReport(results: results)
    }

    /// What a passing shader check reports.
    private static var shadersDetail: String {
        #if canImport(Metal)
        "MetalUI's shader bundle compiled"
        #else
        "MetalUI's SDL shaders were found"
        #endif
    }

    /// Finds MetalUI's shader resource bundle and compiles it on the system's Metal device, as `App()` does. Off macOS
    /// there is nothing to compile at run time: the check finds the SDL backend's compiled shader directory, which
    /// `SDLPlatform` needs to draw (`MetalUISDLShaders` beside the executable, else MetalUI's source tree).
    public static func compileShaders() throws {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        _ = try ShaderLibrary.make(device: device)
        #elseif canImport(MetalUISDL)
        _ = try SDLWindowRenderer.defaultShaderDirectory()
        #else
        // Neither Metal nor MetalUI's SDL backend: nothing here could draw, so the check must not pass silently.
        throw Failure("this build has neither Metal nor MetalUI's SDL backend, so there are no shaders to find.")
        #endif
    }

    /// What a check's detail starts with when the platform has no geometry kernel and the check was left out.
    private static let skippedPrefix = "skipped:"

    private static func check(_ name: String, _ body: @MainActor () async throws -> String) async -> SelfTestResult {
        do {
            return SelfTestResult(name: name, passed: true, detail: try await body())
        } catch let error as KernelError where error == .unavailable {
            return SelfTestResult(name: name, passed: true, detail: "\(skippedPrefix) \(error.userMessage)")
        } catch {
            return SelfTestResult(name: name, passed: false, detail: describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? KernelError)?.userMessage ?? String(describing: error)
    }

    /// A check's own failure, worded for the report.
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
