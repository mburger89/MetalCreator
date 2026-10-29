#if canImport(Metal)
import Foundation
@preconcurrency import Metal
@testable import CreatorImplicit

/// The HLSL engine on this Mac's GPU, for the tests (plan xp-c, X-C2): a kernel source's MSL, made offline from the generated HLSL by the Linux image's
/// SDL_shadercross (`GeneratedKernels.compiled/<digest>.comp.msl`), bound as SDL_GPU's Metal driver binds it (the uniform block at `[[buffer(0)]]`,
/// then the read-only, then the read-write storage buffers). Absent when the kernels were not compiled; a source not compiled throws, naming the script.
/// Given a `RuntimeMSLKernels` it takes the MSL from MetalUI's run-time compiler instead (gap XP-G27).
final class MSLComputeBackend: ImplicitComputeBackend, @unchecked Sendable {
    static let state: ComputeBackendState = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return .absent("no Metal device") }
        guard FileManager.default.fileExists(atPath: GeneratedKernels.compiled.path) else {
            return .absent("the generated kernels were not compiled on this Mac: \(GeneratedKernels.remedy)")
        }
        return .ready(MSLComputeBackend(device: device, queue: queue))
    }()

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let name = "Metal (HLSL)"
    /// Set when the MSL is compiled while the tests run; `nil` reads the kernels compiled offline.
    private let runtimeKernels: RuntimeMSLKernels?
    /// The SDL backends' cap (gap XP-G24), so the tests reach the same limits.
    let largestBuffer = 1 << 27
    var deviceName: String { device.name }

    private init(device: any MTLDevice, queue: any MTLCommandQueue, runtimeKernels: RuntimeMSLKernels? = nil) {
        self.device = device
        self.queue = queue
        self.runtimeKernels = runtimeKernels
    }

    /// A backend whose kernels are compiled from HLSL to MSL at run time by `kernels`; `.absent` without a Metal device.
    static func make(runtimeKernels kernels: RuntimeMSLKernels) -> ComputeBackendState {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return .absent("no Metal device") }
        return .ready(MSLComputeBackend(device: device, queue: queue, runtimeKernels: kernels))
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer, let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return MSLComputeBuffer(buffer)
    }

    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline {
        let text: String
        if let runtimeKernels {
            text = try await runtimeKernels.msl(for: source)
        } else {
            text = try offlineMSL(for: source)
        }
        do {
            let library = try await device.makeLibrary(source: text, options: nil)
            guard let function = library.makeFunction(name: "main0") else {
                throw ImplicitCompileError.engine("\(source.digest): no main0")
            }
            return MSLComputePipeline(try await device.makeComputePipelineState(function: function))
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw ImplicitCompileError.engine(error.localizedDescription)
        }
    }

    /// The MSL compiled offline for `source`, after checking its reflection against the kernel's bindings.
    private func offlineMSL(for source: KernelSource) throws -> String {
        let stem = GeneratedKernels.compiled.appending(path: "\(source.digest).comp")
        guard let text = try? String(contentsOf: stem.appendingPathExtension("msl"), encoding: .utf8) else {
            throw ImplicitCompileError.unsupported(
                "\(source.kernel.rawValue) \(source.digest) was not compiled offline: \(GeneratedKernels.remedy)")
        }
        let reflection = (try? JSONSerialization.jsonObject(with: Data(contentsOf: stem.appendingPathExtension("json")))) as? [String: Int]
        guard reflection?["readonly_storage_buffers"] == source.kernel.bindings.readOnly,
              reflection?["readwrite_storage_buffers"] == source.kernel.bindings.readWrite else {
            throw ImplicitCompileError.engine("\(source.digest).comp.json does not match \(source.kernel.rawValue)'s bindings")
        }
        return text
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        guard batch.isWellFormed, let commands = queue.makeCommandBuffer() else { throw ImplicitCompileError.engine("a malformed batch") }
        try record(batch, into: commands)
        await withCheckedContinuation { continuation in
            commands.addCompletedHandler { _ in continuation.resume() }
            commands.commit()
        }
        if let error = commands.error { throw ImplicitCompileError.engine(error.localizedDescription) }
        return batch.downloads.map { download in
            guard let buffer = download.buffer as? MSLComputeBuffer else { return [] }
            return Array(UnsafeRawBufferPointer(start: buffer.buffer.contents(), count: download.length))
        }
    }

    private func record(_ batch: ComputeBatch, into commands: any MTLCommandBuffer) throws {
        for upload in batch.uploads where !upload.bytes.isEmpty {
            guard let buffer = upload.buffer as? MSLComputeBuffer else { throw ImplicitCompileError.engine("a foreign buffer") }
            upload.bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress {
                    (buffer.buffer.contents() + upload.offset).copyMemory(from: base, byteCount: bytes.count)
                }
            }
        }
        for dispatch in batch.dispatches where dispatch.threads > 0 {
            guard let pipeline = dispatch.pipeline as? MSLComputePipeline, let encoder = commands.makeComputeCommandEncoder() else {
                throw ImplicitCompileError.engine("a foreign pipeline")
            }
            encoder.setComputePipelineState(pipeline.state)
            dispatch.parameters.bytes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setBytes(base, length: bytes.count, index: 0)
            }
            for (slot, buffer) in (dispatch.readOnly + dispatch.readWrite).enumerated() {
                encoder.setBuffer((buffer as? MSLComputeBuffer)?.buffer, offset: 0, index: 1 + slot)
            }
            let groups = (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup
            encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: ImplicitKernel.threadsPerGroup, height: 1, depth: 1))
            encoder.endEncoding()
        }
    }
}
#endif
