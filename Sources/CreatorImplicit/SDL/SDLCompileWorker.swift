#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// The thread the implicit engine's run-time compiles run on (plan xp-c task 11). MetalUI's `SDLGPUShaderCompiler` blocks for tenths of a second to
/// seconds (its docs: "call it off the main actor"; MetalUI `docs/packaging.md` 4b: 0.06 s at 200 lines to 2.7 s at 2,000 on Linux) and is safe from
/// any thread, so it runs here: one `Thread` of our own, jobs in order, never a thread of the cooperative pool (a blocked pool thread starves every
/// task) and never the main thread. It never makes a device (on macOS `SDLGPUDevice.make` hops to the main thread, which must never wait on a thread
/// that waits for it: MetalUI DL-G); the engine's backend made its device before any compile. Serial on purpose: one DXC at a time bounds the memory
/// and the CPU taken from the preview. The pattern is MetalUI's `SDLGPUWorker`. A compile cannot be cancelled: a stale one finishes and is cached by
/// its digest (the shape may come back). The thread lives as long as the process.
final class SDLCompileWorker: @unchecked Sendable {
    // @unchecked: `jobs` is read and written only while `condition` is locked; the rest is immutable.
    static let shared = SDLCompileWorker()

    private struct Job {
        let source: KernelSource
        let libraryPath: String?
        let device: SDLGPUDevice
        let continuation: CheckedContinuation<SDLGPUComputePipeline, any Error>
    }

    private let condition = NSCondition()
    private var jobs: [Job] = []

    private init() {
        let thread = Thread { [self] in run() }
        thread.name = "MetalCreator implicit compiler"
        // DXC recurses deeply on a long kernel; Windows gives a new thread 1 MB unless told (the test executables reserve 16 MB, xp-1).
        thread.stackSize = 16 << 20
        thread.start()
    }

    /// `source` compiled for `device` (its driver's format: SPIR-V on Vulkan, DXIL on Direct3D 12), after every earlier job. Throws
    /// `ImplicitCompileError.engine` with MetalUI's text (`compileFailed`: DXC's diagnostics) or SDL's.
    func pipeline(for source: KernelSource, libraryPath: String?, device: SDLGPUDevice) async throws -> SDLGPUComputePipeline {
        try await withCheckedThrowingContinuation { continuation in
            condition.lock()
            jobs.append(Job(source: source, libraryPath: libraryPath, device: device, continuation: continuation))
            condition.signal()
            condition.unlock()
        }
    }

    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            do {
                job.continuation.resume(returning: try Self.compile(job.source, libraryPath: job.libraryPath, device: job.device))
            } catch {
                job.continuation.resume(throwing: error)
            }
        }
    }

    /// The blocking compile, on this worker's thread only.
    private static func compile(_ source: KernelSource, libraryPath: String?,
                                device: SDLGPUDevice) throws(ImplicitCompileError) -> SDLGPUComputePipeline {
        let blob: SDLGPUShaderBlob
        do {
            blob = try SDLGPUShaderCompiler.shared(libraryPath: libraryPath)
                .compileCompute(name: "\(source.kernel.rawValue)-\(source.digest)", hlsl: source.text, for: device)
        } catch {
            // `compileFailed(stage:diagnostics:)` carries DXC's text with file, line and column; the other cases name their problem.
            throw .engine("\(source.kernel.rawValue) \(source.digest): \(error)")
        }
        let bindings = source.kernel.bindings
        guard blob.readOnlyStorageBuffers == bindings.readOnly, blob.readWriteStorageBuffers == bindings.readWrite else {
            throw .engine("\(source.digest)'s reflection (\(blob.readOnlyStorageBuffers) read-only, "
                + "\(blob.readWriteStorageBuffers) read-write) does not match \(source.kernel.rawValue)'s bindings")
        }
        do {
            return try device.compileComputePipeline(blob)
        } catch {
            throw .engine("\(source.kernel.rawValue): \(error)")
        }
    }
}
#endif
