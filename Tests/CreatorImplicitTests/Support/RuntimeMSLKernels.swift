#if canImport(Metal) && canImport(MetalUIShaderRuntime)
import Foundation
import MetalUIShaderRuntime
@testable import CreatorImplicit

/// The generated HLSL compiled to MSL while the tests run on a Mac (gap XP-G27, MetalUI `abc2bf46`): `MetalUIShaderRuntime`'s `RuntimeShaderCompiler`
/// with the `.msl` target, whose entry point is `main0`, fed to `MSLComputeBackend` as `SDLRuntimeKernels` feeds `SDLComputeBackend`. Test-only: the
/// shipping Mac app runs native Metal. The library is found by MetalUI's lookup (`METALUI_SHADERCROSS_LIB`, with `libSDL3.0.dylib` beside it).
struct RuntimeMSLKernels: Sendable {
    let libraryPath: String?

    init(libraryPath: String? = nil) {
        self.libraryPath = libraryPath
    }

    /// `nil` when MetalUI's compiler loads (the first call loads it for the process), else `.absent` with MetalUI's error.
    var unavailability: ComputeBackendState? {
        do {
            _ = try RuntimeShaderCompiler.shared(libraryPath: libraryPath)
            return nil
        } catch {
            return .absent("MetalUI's run-time shader compiler did not load (gap XP-G27; set METALUI_SHADERCROSS_LIB to a macOS "
                + "SDL3_shadercross lib directory that also holds libSDL3.0.dylib): \(error)")
        }
    }

    /// The MSL for `source`, compiled on a thread of its own (the compile blocks, and DXC recurses deeply on a long kernel). Throws
    /// `ImplicitCompileError.engine` with MetalUI's text, or when the reflection does not match the kernel's bindings.
    func msl(for source: KernelSource) async throws -> String {
        let libraryPath = libraryPath
        let compiled: CompiledComputeShader
        do {
            compiled = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CompiledComputeShader, any Error>) in
                let thread = Thread {
                    continuation.resume(with: Result {
                        try RuntimeShaderCompiler.shared(libraryPath: libraryPath).compileCompute(
                            hlsl: source.text, entryPoint: "main", target: .msl)
                    })
                }
                thread.name = "MetalCreator implicit MSL compiler"
                thread.stackSize = 16 << 20
                thread.start()
            }
        } catch {
            throw ImplicitCompileError.engine("\(source.kernel.rawValue) \(source.digest): \(error)")
        }
        let bindings = source.kernel.bindings
        guard compiled.reflection.readOnlyStorageBuffers == bindings.readOnly,
              compiled.reflection.readWriteStorageBuffers == bindings.readWrite else {
            throw ImplicitCompileError.engine("\(source.digest)'s reflection does not match \(source.kernel.rawValue)'s bindings")
        }
        guard compiled.entryPoint == "main0", let text = String(bytes: compiled.bytes, encoding: .utf8) else {
            throw ImplicitCompileError.engine("\(source.digest): the compiler's MSL is not text with a main0")
        }
        return text
    }
}
#endif
