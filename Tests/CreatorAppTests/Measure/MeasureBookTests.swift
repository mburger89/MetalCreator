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
    /// A box over `FakeKernel` with a bottom and a top edge named as a kept measurement's anchors: their distance is the box's height.
    @MainActor
    struct Fixture {
        let fixture: MeasureAppFixture
        let measurement: KeptMeasurement

        var app: AppModel { fixture.app }
        var book: MeasureBook { fixture.app.measureBook }

        static func open(kernel: FakeKernel = FakeKernel()) async throws -> Fixture {
            let fixture = await MeasureAppFixture.open(kernel: kernel)
            return Fixture(fixture: fixture, measurement: try heightOf(fixture.solid, in: fixture.app))
        }

        static func heightOf(_ solid: Solid, in app: AppModel) throws -> KeptMeasurement {
            try heightOf(solid, index: 0, in: app.measureScene())
        }

        /// The bottom and the top edge along x on one side of a part: edges, so the kernel measures them (points are Swift's).
        static func heightOf(_ solid: Solid, index: Int, in scene: MeasureScene) throws -> KeptMeasurement {
            let along = solid.topology.edges.filter { edge in
                guard case .line? = edge.curve, let direction = edge.direction else { return false }
                return abs(abs(direction.x) - 1) < 1e-9
            }
            func start(_ edge: EdgeInfo) -> Vector3 { edge.curve?.ends[0] ?? .zero }
            let bottom = try #require(along.min { (start($0).z, start($0).y) < (start($1).z, start($1).y) })
            let top = try #require(along.filter { abs(start($0).y - start(bottom).y) < 1e-9 }.max { start($0).z < start($1).z })
            let anchors = try [bottom, top].map { edge in
                try #require(MeasureResolver.anchor(for: .edge(solid: index, edge.id), in: scene))
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

    @Test func keptDistancesAreNotRemeasuredAcrossASketch() async throws {
        let kernel = FakeKernel()
        let calls = Mutex(0)
        await kernel.setMeasureHook { calls.withLock { $0 += 1 } }
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = await makeApp(builder.graph, kernel: kernel)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        app.measureBook.add(try Fixture.heightOf(app.viewport.items[0].solid, in: app))
        await app.settle()
        let before = calls.withLock { $0 }
        #expect(before >= 1)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        try #require(app.sketch != nil)
        try #require(app.sketch).editor.finish()
        await app.settle()
        #expect(app.sketch == nil)
        #expect(calls.withLock { $0 } == before, "nothing was edited, so nothing is measured again")
        #expect(app.measureBook.entries[0].picks?.count == 2)
    }

    @Test func aReturningBasisIgnoresTheInFlightResultOfTheOldOne() async throws {
        let kernel = FakeKernel()
        let calls = Mutex(0)
        let held = Mutex<[Int: DispatchSemaphore]>([2: DispatchSemaphore(value: 0), 3: DispatchSemaphore(value: 0)])
        await kernel.setMeasureHook {
            let number = calls.withLock { count -> Int in count += 1; return count }
            if let gate = held.withLock({ $0[number] }) { _ = gate.wait(timeout: .now() + 10) }
        }
        let fixture = await MeasureAppFixture.open(kernel: kernel)
        // The test's own book: the app's refreshes would resolve the anchors against the app's scene.
        let book = MeasureBook(kernel: kernel, document: fixture.app.document)
        let profile = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let xNode = NodeID(), yNode = NodeID()
        func part(_ node: NodeID, _ height: Double) async throws -> Solid {
            try await kernel.extrude(profile, distance: height, mode: .oneSided, tag: NodeTag(node: node, item: 0))
        }
        func scene(_ solids: [Solid]) -> MeasureScene {
            MeasureScene(solids: solids, pickable: solids.map { _ in true }, parts: [], plane: nil)
        }
        func height(of index: Int, in scene: MeasureScene) throws -> KeptMeasurement {
            try Fixture.heightOf(scene.solids[index], index: index, in: scene)
        }
        let sceneA = scene([try await part(xNode, 10), try await part(yNode, 7)])
        let sceneB = scene([try await part(xNode, 20), sceneA.solids[1]])
        let x = try height(of: 0, in: sceneA), y = try height(of: 1, in: sceneA)
        fixture.app.document.measurements = [x, y]
        book.refresh(sceneA)
        // X measures at A (call 1) while Y (call 2) is held.
        for _ in 0..<2000 where book.entries[0].distance == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(abs(try #require(book.entries[0].distance).distance - 10) < 1e-9)
        // X moves to B (call 3, held), then back to A while Y keeps the task alive.
        book.refresh(sceneB)
        book.refresh(sceneA)
        #expect(abs(try #require(book.entries[0].distance).distance - 10) < 1e-9)
        for number in [2, 3] { held.withLock { $0[number] }?.signal() }
        await book.waitForDistances()
        #expect(abs(try #require(book.entries[0].distance).distance - 10) < 1e-9, "B's late result did not land")
        #expect(!book.entries[0].isMeasuring)
        #expect(abs(try #require(book.entries[1].distance).distance - 7) < 1e-9)
        // B's result was not stored as A's: measuring at B again asks the kernel.
        let before = calls.withLock { $0 }
        book.refresh(sceneB)
        await book.waitForDistances()
        #expect(calls.withLock { $0 } > before)
        #expect(abs(try #require(book.entries[0].distance).distance - 20) < 1e-9)
    }
}
