import Testing
@testable import CreatorApp

/// The export's Cancel (implicit spec §5.3).
@MainActor
struct ExportRunTests {
    @Test func aCancelBeforeTheStopperIsSetIsReplayedWhenItIs() {
        let run = ExportRun(title: "Exporting")
        run.cancel()
        var stopped = false
        run.onCancel = { stopped = true }
        #expect(run.isCancelling && stopped)
    }

    @Test func aCancelAfterTheStopperIsSetCallsItOnce() {
        let run = ExportRun(title: "Exporting")
        var stops = 0
        run.onCancel = { stops += 1 }
        run.cancel()
        #expect(stops == 1)
    }
}
