#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The SDL renderer's suites disable themselves when no SDL_GPU device answers, so a runner without a GPU would pass them by running
/// none. Where the environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image runs Mesa's lavapipe, a CPU Vulkan driver, and
/// `scripts/linux-test.sh` sets it; the Windows job runs Direct3D 12 on WARP), this test fails instead, naming why.
@MainActor
struct SDLGPUAvailabilityTests {
    @Test func aDeviceAnswersWhereTheEnvironmentPromisesOne() throws {
        let required = ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1"
        try #require(!required || SDLTestDevice.isAvailable, "XP_REQUIRE_GPU=1 but no device: \(SDLGPUDevice.lastFailure)")
    }

    @Test(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
    func theShaderLibraryAndEveryPipelineAreMade() throws {
        let device = try #require(SDLTestDevice.shared)
        let library = try SDLViewportShaders.library()
        _ = try SDLViewportPipelines(device: device, library: library)
    }
}
#endif
