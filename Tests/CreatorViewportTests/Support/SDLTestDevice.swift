// Test fixture file: the SDL_GPU device the renderer tests share, and what a batch's recording closure is handed.
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// A value handed to a batch's recording closure, which runs on the device's worker thread. The test awaits the batch before it
/// touches the value again, so nothing else does meanwhile.
struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

struct SDLRigError: Error, CustomStringConvertible {
    let description: String
}

/// The device the SDL renderer tests share: Vulkan on Mesa's lavapipe in the Linux image, Direct3D 12 on WARP on Windows runners. `nil`
/// when no GPU or driver answers, which disables the suites (named, not assumed: ``SDLGPUAvailabilityTests`` fails instead where the
/// environment promises a GPU).
enum SDLTestDevice {
    static let shared: SDLGPUDevice? = SDLGPUDevice.make()
    static var isAvailable: Bool { shared != nil }

    /// The viewport's pipelines on the shared device, made once: making them compiles every shader (a CPU driver takes about a second),
    /// and a test that made its own would hold the main actor for that long, long enough to starve the timing tests that share it.
    static let pipelines: SDLViewportPipelines? = shared.flatMap { device in
        (try? SDLViewportShaders.library()).flatMap { try? SDLViewportPipelines(device: device, library: $0) }
    }
}
#endif
