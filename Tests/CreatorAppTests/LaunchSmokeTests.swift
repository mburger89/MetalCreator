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

    @Test func aViewportThatDrewPassesAndSaysHowOften() {
        let smoke = LaunchSmoke(seconds: 5)
        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 3, failure: nil) }
        #expect(!smoke.passed, "no first frame yet")
        smoke.frameReached()
        #expect(smoke.passed)
        #expect(smoke.report == "MetalCreator smoke test: reached the first frame and the 3D viewport drew 3 frames, ran 5 s.")
        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 1, failure: nil) }
        #expect(smoke.report.contains("drew 1 frame,"))
    }

    @Test func aViewportThatDrewNothingFailsTheRunAndSaysWhy() {
        let smoke = LaunchSmoke(seconds: 5)
        smoke.frameReached()
        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 0, failure: "The GPU could not create a pipeline.") }
        #expect(!smoke.passed)
        #expect(smoke.report == "MetalCreator smoke test: reached the first frame, but the 3D viewport drew nothing: "
            + "The GPU could not create a pipeline.")
        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 0, failure: nil) }
        #expect(!smoke.passed)
        #expect(smoke.report.hasSuffix("drew nothing (it was never asked to draw)."))
    }
}
