#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// The HLSL engine over MetalUI's SDL_GPU compute (MetalUI S5; plan xp-c): an owned, headless device (MetalUI: `make` is nonisolated, safe off the
/// main thread once `SDLPlatform` has initialised video, which the app does first), pipelines from a `SDLKernelProvider`, one `submitBatch` per batch,
/// its fence awaited so no thread blocks. No raw `SDL_` call.
final class SDLComputeBackend: ImplicitComputeBackend {
    static var platformName: String {
        #if os(Windows)
        "Direct3D 12"
        #else
        "Vulkan"
        #endif
    }

    let device: SDLGPUDevice
    let kernels: any SDLKernelProvider
    let name = SDLComputeBackend.platformName
    /// The driver's name until XP-G23 is adopted (task 13).
    var deviceName: String { name }
    /// Vulkan's guaranteed `maxStorageBufferRange` until XP-G24 is adopted (task 13).
    let largestBuffer = 1 << 27

    private init(device: SDLGPUDevice, kernels: any SDLKernelProvider) {
        self.device = device
        self.kernels = kernels
    }

    /// `.absent` without a device; the provider's own reason when it cannot give kernels here.
    static func make(kernels: any SDLKernelProvider) -> ComputeBackendState {
        if let unavailable = kernels.unavailability { return unavailable }
        guard let device = SDLGPUDevice.make() else { return .absent("no SDL_GPU device: \(SDLGPUDevice.lastFailure)") }
        return .ready(SDLComputeBackend(device: device, kernels: kernels))
    }

    func makeBuffer(length: Int) throws -> any ComputeBuffer {
        guard length <= largestBuffer,
              let buffer = device.makeBuffer(size: max(length, 16), usage: [.computeStorageRead, .computeStorageWrite]) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes")
        }
        return SDLComputeBuffer(buffer)
    }

    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline {
        SDLComputePipeline(try await kernels.pipeline(for: source, device: device))
    }

    func run(_ batch: ComputeBatch) async throws -> [[UInt8]] {
        let recording = try SDLComputeRecording(batch, device: device)
        let fence = try await device.submitBatch { commandBuffer in recording.record(into: commandBuffer) }
        await fence.wait()
        if recording.hasFailed { throw ImplicitCompileError.engine("SDL_GPU refused a compute pass") }
        return recording.read()
    }
}
#endif
