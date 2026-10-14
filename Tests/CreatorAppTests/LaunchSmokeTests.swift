import Testing
@testable import CreatorApp

/// `--smoke-test` (CI): the verdict printed when the time is up.
@MainActor
struct LaunchSmokeTests {
    @Test func aRunThatNeverDrewAFrameFails() {
        let smoke = LaunchSmoke()
        #expect(!smoke.passed)
        #expect(smoke.report == "MetalCreator smoke test: no frame was drawn in 5 s.")
    }

    @Test func aRunThatReachedItsFirstFramePasses() {
        let smoke = LaunchSmoke(seconds: 2.5)
        smoke.frameReached()
        #expect(smoke.passed)
        #expect(smoke.report == "MetalCreator smoke test: reached the first frame, ran 2.5 s.")
    }
}
