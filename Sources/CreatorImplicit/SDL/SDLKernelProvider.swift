#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Where a kernel source's device bytes come from (plan xp-c): MetalUI's run-time compiler in the app (`SDLRuntimeKernels`, task 11,
/// gap XP-G25), and, before it and in the tests, the generated kernels compiled offline (`SDLPrecompiledKernels`).
protocol SDLKernelProvider: Sendable {
    /// Whether this provider can give anything here; `nil` when it can, else why not (`.absent` or `.broken` of the backend).
    var unavailability: ComputeBackendState? { get }
    func pipeline(for source: KernelSource, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline
}

/// The generated kernels compiled offline by `scripts/linux-test.sh kernels` (task 3): `<digest>.comp.{spv,dxil,msl,json}` in one directory.
struct SDLPrecompiledKernels: SDLKernelProvider {
    let directory: URL

    var unavailability: ComputeBackendState? {
        FileManager.default.fileExists(atPath: directory.path)
            ? nil : .absent("the generated kernels were not compiled (\(directory.path))")
    }

    func pipeline(for source: KernelSource, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline {
        let blob: SDLGPUShaderBlob
        do {
            blob = try SDLGPUShaderLibrary(directory: directory).compute("\(source.digest)", for: device)
        } catch {
            throw ImplicitCompileError.unsupported("\(source.kernel.rawValue) \(source.digest) was not compiled offline "
                + "(run XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels): \(error)")
        }
        let bindings = source.kernel.bindings
        guard blob.readOnlyStorageBuffers == bindings.readOnly, blob.readWriteStorageBuffers == bindings.readWrite else {
            throw ImplicitCompileError.engine("\(source.digest)'s reflection does not match \(source.kernel.rawValue)'s bindings")
        }
        do {
            return try device.compileComputePipeline(blob)
        } catch {
            throw ImplicitCompileError.engine("\(source.kernel.rawValue): \(error)")
        }
    }
}
#endif
