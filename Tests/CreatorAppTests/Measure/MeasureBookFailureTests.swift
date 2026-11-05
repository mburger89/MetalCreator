import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Synchronization
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A distance the kernel refuses: kept measurements say so and do not ask again until something under them changes.
@MainActor
struct MeasureBookFailureTests {
    typealias Fixture = MeasureBookTests.Fixture

    @Test func aKeptFailedDistanceSaysSo() async throws {
        let kernel = FakeKernel()
        await kernel.setMeasureHook { throw KernelError.invalidInput("Those can't be measured.") }
        let fixture = try await Fixture.open(kernel: kernel)
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        let entry = fixture.book.entries[0]
        #expect(entry.distance == nil && entry.distanceFailed && !entry.isMeasuring)
        #expect(MeasurePanelText.keptSummary(entry, units: fixture.app.units) == MeasurePanelText.distanceFailed + " · Angle 0°",
                "the failed distance stays unlabelled, the angle keeps its row")
        #expect(fixture.book.dimensions(style: DimensionStyle.ansi, units: fixture.app.units).isEmpty)
        fixture.book.remove(fixture.measurement.id)
        #expect(fixture.book.entries.isEmpty)
    }

    @Test func aFailedDistanceIsNotRetriedUntilAnEdit() async throws {
        let kernel = FakeKernel()
        let calls = Mutex(0)
        let refuses = Mutex(true)
        await kernel.setMeasureHook {
            calls.withLock { $0 += 1 }
            if refuses.withLock({ $0 }) { throw KernelError.invalidInput("Those can't be measured.") }
        }
        let fixture = try await Fixture.open(kernel: kernel)
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        #expect(calls.withLock { $0 } == 1)
        fixture.book.refresh(fixture.app.measureScene())
        await fixture.app.settle()
        #expect(calls.withLock { $0 } == 1, "the same basis fails the same way")
        #expect(fixture.book.entries[0].distanceFailed)
        refuses.withLock { $0 = false }
        try fixture.setHeight(25)
        await fixture.app.settle()
        #expect(calls.withLock { $0 } == 2)
        let entry = fixture.book.entries[0]
        #expect(!entry.distanceFailed)
        #expect(abs(try #require(entry.distance).distance - 25) < 1e-9)
    }
}
