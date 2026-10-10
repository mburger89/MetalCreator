import CreatorKernel
import Observation
import Testing
@testable import CreatorViewport

/// The view's size reaches observers (gap M4-a's stopgap): the draw records it untracked, and one task later bumps
/// the observed `viewSizeChanges`, so whatever lays out from `observedViewSize` (the app's graph panel and its
/// culling) is rebuilt after a resize.
@MainActor
struct ViewSizeObservationTests {
    /// Counts observation callbacks.
    @MainActor
    final class Observer {
        var changes = 0
    }

    func observing(_ model: ViewportModel) -> Observer {
        let observer = Observer()
        withObservationTracking { _ = model.observedViewSize } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        return observer
    }

    @Test func aNewSizeReachesObserversOneTaskAfterTheDraw() async {
        let model = ViewportModel(kernel: FakeKernel())
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        await model.sizeChangeTask?.value
        let observer = observing(model)
        model.recordViewSize(ViewportSize(width: 1200, height: 800))
        #expect(observer.changes == 0, "the draw writes no tracked state")
        #expect(model.observedViewSize == ViewportSize(width: 1200, height: 800), "read at once, it is the new size")
        await model.sizeChangeTask?.value
        #expect(observer.changes == 1, "one task later, its readers are invalidated")
    }

    @Test func theSameSizeAgainNotifiesNoOne() async {
        let model = ViewportModel(kernel: FakeKernel())
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        await model.sizeChangeTask?.value
        let changes = model.viewSizeChanges
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        #expect(model.sizeChangeTask == nil, "nothing scheduled: every frame records the same size")
        #expect(model.viewSizeChanges == changes)
    }
}
