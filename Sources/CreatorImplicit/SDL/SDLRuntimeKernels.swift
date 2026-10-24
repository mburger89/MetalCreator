#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// The implicit engine's kernels compiled while the app runs (plan xp-c task 11; MetalUI XP-G25, `SDLGPUShaderCompiler`, MetalUI `722f0cd6`): HLSL
/// text in, a pipeline out, on `SDLCompileWorker`'s thread; the engine caches the pipelines by the source's digest. The library is found by MetalUI's
/// lookup (`METALUI_SHADERCROSS_LIB` in the tests and CI; a zip's DLLs beside the `.exe`; a tarball's or AppImage's `lib/` through the loader path, the
/// executable's `$ORIGIN/lib` RUNPATH: gap XP-G26). `libraryPath` names a library explicitly (a test's missing one).
struct SDLRuntimeKernels: SDLKernelProvider {
    let libraryPath: String?

    init(libraryPath: String? = nil) {
        self.libraryPath = libraryPath
    }

    /// `nil` when MetalUI's compiler loads (the first call loads it for the process, in a few milliseconds), else `.broken` with MetalUI's error:
    /// `compilerUnavailable` lists every path tried (X-C4: the person hears "Running on the CPU").
    var unavailability: ComputeBackendState? {
        do {
            _ = try SDLGPUShaderCompiler.shared(libraryPath: libraryPath)
            return nil
        } catch {
            return .broken("the implicit engine's shader compiler did not load: \(error)")
        }
    }

    func pipeline(for source: KernelSource, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline {
        try await SDLCompileWorker.shared.pipeline(for: source, libraryPath: libraryPath, device: device)
    }
}
#endif
