import Foundation
import Testing
@testable import CreatorImplicit

/// Where the environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image's lavapipe, the Windows job's WARP) the HLSL engine must have a backend,
/// so a runner that lost its driver cannot pass the agreement suites by skipping them.
struct ImplicitGPUAvailabilityTests {
    @Test func theHLSLEngineAnswersWhereTheEnvironmentPromisesAGPU() async {
        guard ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1" else { return }
        #if canImport(MetalUISDLGPU)
        #expect(GPUEnginesUnderTest.hlsl != nil, "XP_REQUIRE_GPU=1 but \(GPUEnginesUnderTest.unavailableReason)")
        // Read once: an `await` cannot sit in the message's autoclosure.
        let availability = await HLSLImplicitEngine.sdl.availability
        #expect(availability == .available, "XP_REQUIRE_GPU=1 but the app's engine cannot run: \(availability)")
        #endif
    }
}
