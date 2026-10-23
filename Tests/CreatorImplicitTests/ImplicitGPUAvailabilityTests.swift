import Foundation
import Testing
@testable import CreatorImplicit

/// Where the environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image's lavapipe, the Windows job's WARP) the HLSL engine must have a backend,
/// so a runner that lost its driver cannot pass the agreement suites by skipping them.
struct ImplicitGPUAvailabilityTests {
    @Test func theHLSLEngineAnswersWhereTheEnvironmentPromisesAGPU() {
        guard ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1" else { return }
        #if canImport(MetalUISDLGPU) && !os(Windows)
        #expect(GPUEnginesUnderTest.hlsl != nil, "XP_REQUIRE_GPU=1 but \(GPUEnginesUnderTest.unavailableReason)")
        #endif
    }
}
