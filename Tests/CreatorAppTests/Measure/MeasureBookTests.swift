import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Synchronization
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The kept measurements: view state that follows the model, off the undo stack, drawn with Measure on or off.
@MainActor
struct MeasureBookTests {
    /// A box over `FakeKernel` with the two ends of a vertical edge named as a kept measurement's anchors: their distance is
    /// the box's height.
    @MainActor
    private struct Fixture {
        let fixture: MeasureAppFixture
        let measurement: KeptMeasurement

        var app: AppModel { fixture.app }
        var book: MeasureBook { fixture.app.measureBook }

        static func open(kernel: FakeKernel = FakeKernel()) async throws -> Fixture {
            let fixture = await MeasureAppFixture.open(kernel: kernel)
            return Fixture(fixture: fixture, measurement: try heightOf(fixture.solid, in: fixture.app))
        }

        static func heightOf(_ solid: Solid, in app: AppModel) throws -> KeptMeasurement {
            let edge = try #require(solid.topology.edges.first { edge in
                guard case .line? = edge.curve, let direction = edge.direction else { return false }
                return abs(abs(direction.z) - 1) < 1e-9
            })
            let ends = try #require(edge.curve?.ends)
            let scene = app.measureScene()
            let anchors = try [(CornerEnd.start, ends[0]), (.end, ends[1])].map { end, point in
                try #require(MeasureResolver.anchor(for: .corner(solid: 0, edge.id, end, at: point), in: scene))
            }
            return KeptMeasurement(anchors: anchors)
        }

        func setHeight(_ value: Double) throws {
            try app.document.perform(.setInput(fixture.box.extrude.id, "distance", .number(value)))
        }
    }

    @Test func keepingMakesNoUndoStepAndNoEdit() async throws {
        let fixture = try await Fixture.open()
        let app = fixture.app
        try fixture.setHeight(12)
        await app.settle()
        let title = app.undoTitle
        #expect(app.isEdited)
        let before = app.document.content
        app.measureBook.add(fixture.measurement)
        await app.settle()
        #expect(app.document.measurements.count == 1)
        #expect(app.document.content == before)
        #expect(app.undoTitle == title)
        app.undo()
        await app.settle()
        #expect(app.document.measurements.count == 1, "undoing an earlier edit leaves the measurement")
    }

    @Test func aKeptDistanceFollowsAWallEdit() async throws {
        let fixture = try await Fixture.open()
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        #expect(abs(try #require(fixture.book.entries[0].distance).distance - 10) < 1e-9)
        try fixture.setHeight(25)
        await fixture.app.settle()
        let entry = fixture.book.entries[0]
        #expect(entry.picks?.count == 2)
        #expect(abs(try #require(entry.distance).distance - 25) < 1e-9)
        #expect(!entry.isMeasuring)
    }

    @Test func aLostPickReadsNoLongerFound() async throws {
        let fixture = try await Fixture.open()
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        #expect(!fixture.app.measureDimensions().isEmpty)
        try fixture.app.document.perform(.removeNode(fixture.fixture.box.extrude.id))
        await fixture.app.settle()
        #expect(fixture.book.entries[0].picks == nil)
        #expect(fixture.app.measureDimensions().isEmpty)
        #expect(fixture.app.document.measurements.count == 1, "a lost measurement stays")
    }

    @Test func aNewerRefreshDropsAnOlderDistance() async throws {
        let kernel = FakeKernel()
        let gate = FirstCallGate()
        await kernel.setMeasureHook { gate.enter() }
        let fixture = try await Fixture.open(kernel: kernel)
        let app = fixture.app
        fixture.book.add(fixture.measurement)
        try fixture.setHeight(30)
        await app.document.waitForEvaluation()
        if let task = app.sceneTask { await task.value }
        gate.release()
        await app.settle()
        let entry = fixture.book.entries[0]
        #expect(abs(try #require(entry.distance).distance - 30) < 1e-9)
        #expect(!entry.isMeasuring)
    }

    @Test func anUnchangedRefreshLetsTheRunningDistanceFinish() async throws {
        let kernel = FakeKernel()
        let gate = FirstCallGate()
        let calls = Mutex(0)
        await kernel.setMeasureHook {
            calls.withLock { $0 += 1 }
            gate.enter()
        }
        let fixture = try await Fixture.open(kernel: kernel)
        fixture.book.add(fixture.measurement)
        fixture.book.refresh(fixture.app.measureScene())
        fixture.book.refresh(fixture.app.measureScene())
        gate.release()
        await fixture.app.settle()
        #expect(calls.withLock { $0 } == 1, "the running measurement was not asked for again")
        #expect(abs(try #require(fixture.book.entries[0].distance).distance - 10) < 1e-9)
        #expect(!fixture.book.entries[0].isMeasuring)
    }

    @Test func removingAnEntryWhileItMeasuresDropsTheLateResult() async throws {
        let kernel = FakeKernel()
        let gate = FirstCallGate()
        await kernel.setMeasureHook { gate.enter() }
        let fixture = try await Fixture.open(kernel: kernel)
        fixture.book.add(fixture.measurement)
        fixture.book.remove(fixture.measurement.id)
        gate.release()
        await fixture.app.settle()
        #expect(fixture.book.entries.isEmpty)
        #expect(fixture.app.document.measurements.isEmpty)
    }

    @Test func savedMeasurementsResolveAfterOpen() async throws {
        let fixture = try await Fixture.open()
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture.app.save(to: url)
        let reopened = AppModel(kernel: FakeKernel())
        try reopened.open(url)
        #expect(reopened.measureBook.entries.count == 1)
        #expect(reopened.measureBook.entries[0].picks == nil, "nothing resolves before the first evaluation")
        await reopened.settle()
        #expect(reopened.measureBook.entries[0].picks?.count == 2)
        #expect(abs(try #require(reopened.measureBook.entries[0].distance).distance - 10) < 1e-9)
    }

    @Test func newClearsThem() async throws {
        let fixture = try await Fixture.open()
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        fixture.app.newDocument()
        await fixture.app.settle()
        #expect(fixture.app.document.measurements.isEmpty)
        #expect(fixture.app.measureBook.entries.isEmpty)
    }

    @Test func keptOnesDrawOutsideMeasure() async throws {
        let fixture = try await Fixture.open()
        fixture.book.add(fixture.measurement)
        await fixture.app.settle()
        #expect(fixture.app.measure == nil)
        let ids = fixture.app.measureDimensions().map(\.id.rawValue)
        #expect(!ids.isEmpty)
        #expect(ids.allSatisfy { $0.hasPrefix("kept/\(fixture.measurement.id.uuidString)/") })
        #expect(fixture.app.viewport.dimensions.map(\.id.rawValue) == ids)
    }

    @Test func keptOnesDoNotDrawInSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        app.measureBook.add(try Fixture.heightOf(app.viewport.items[0].solid, in: app))
        await app.settle()
        #expect(!app.measureDimensions().isEmpty)
        app.beginSketch(for: box.sketch.id)
        #expect(app.sketch != nil)
        #expect(app.measureDimensions().isEmpty)
    }
}
