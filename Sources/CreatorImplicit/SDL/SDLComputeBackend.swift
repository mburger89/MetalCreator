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
    /// The adapter's name (MetalUI XP-G23: SDL's string, shown and never parsed), " (software)" on lavapipe or WARP (X-C5: used like any GPU); the
    /// platform's name where SDL gives none.
    let deviceName: String
    /// SDL_GPU's guaranteed storage-buffer floor (MetalUI XP-G24: `limits` are floors, not the device's limits; 2^27 bytes on every backend).
    let largestBuffer: Int

    private init(device: SDLGPUDevice, kernels: any SDLKernelProvider) {
        self.device = device
        self.kernels = kernels
        let adapter = device.adapterName ?? SDLComputeBackend.platformName
        deviceName = device.isSoftwareRasterizer ? adapter + " (software)" : adapter
        largestBuffer = device.limits.maxStorageBufferBindingBytes
    }

    /// `.absent` without a device; then the provider's own reason when it cannot give kernels here.
    static func make(kernels: any SDLKernelProvider) -> ComputeBackendState {
        guard let device = SDLGPUDevice.make() else { return .absent("no SDL_GPU device: \(SDLGPUDevice.lastFailure)") }
        guard device.limits.maxComputeWorkgroupCount.x >= ComputeBytes.maximumGroups else {
            let groups = device.limits.maxComputeWorkgroupCount.x
            return .broken("SDL_GPU allows \(groups) groups a dispatch, fewer than the engine's \(ComputeBytes.maximumGroups)")
        }
        if let unavailable = kernels.unavailability { return unavailable }
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
