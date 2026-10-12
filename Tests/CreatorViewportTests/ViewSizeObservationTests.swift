import CreatorGeometry
import CreatorKernel
import Foundation
import Observation
import Testing
@testable import CreatorViewport

/// The view's size reaches observers (gap M4-a): `ViewportView`'s `onGeometryChange` records it into the tracked
/// `viewSize`, so whatever is built from it (the handle and overlay labels, the app's graph panel placement and its
/// culling) is rebuilt after a resize.
@MainActor
struct ViewSizeObservationTests {
    /// Counts observation callbacks.
    @MainActor
    final class Observer {
        var changes = 0
    }

    @Test func aNewSizeReachesObserversAtOnce() {
        let model = ViewportModel(kernel: FakeKernel())
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        let observer = Observer()
        withObservationTracking { _ = model.viewSize } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        model.recordViewSize(ViewportSize(width: 1200, height: 800))
        #expect(observer.changes == 1, "its readers are invalidated by the write")
        #expect(model.viewSize == ViewportSize(width: 1200, height: 800))
    }

    @Test func theSameSizeAgainNotifiesNoOne() {
        let model = ViewportModel(kernel: FakeKernel())
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        let observer = Observer()
        withObservationTracking { _ = model.viewSize } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        model.recordViewSize(ViewportSize(width: 800, height: 600))
        #expect(observer.changes == 0, "nothing is written when the size has not changed")
    }

    /// The handle labels read the size as the overlay labels do. A saved camera shows the handles on the first build,
    /// before the layout has reported the size: that build must be rebuilt once it has.
    @Test func handleLabelsAreRebuiltWhenTheLayoutReportsTheFirstSize() {
        let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                               projection: .orthographic)
        let model = ViewportModel(kernel: FakeKernel(), pose: front)
        model.showHandles([ViewportHandle(id: "r", anchor: .zero, direction: .unitZ, value: 3, range: 0...10,
                                          style: .radial, tint: .feature),
        ])
        let observer = Observer()
        withObservationTracking { _ = model.handleLabels() } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        #expect(model.handleLabels().isEmpty, "no size yet")
        model.recordViewSize(ViewportSize(width: 400, height: 300))
        #expect(observer.changes == 1, "the labels' reader is invalidated by the first size")
        #expect(model.handleLabels().map(\.text) == ["R 3 mm"])
    }
}
