import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The Measure tool's picking, distance and drawing, driven through the tool's own methods on a box over `FakeKernel`.
@MainActor
struct MeasureSessionTests {
    @Test func clickingTwoEdgesMeasuresTheirDistance() async throws {
        let fixture = await MeasureAppFixture.open()
        let app = fixture.app
        app.setMeasure(true)
        let (a, b) = (fixture.verticals[0], fixture.verticals[1])
        fixture.click(fixture.target(a))
        fixture.click(fixture.target(b))
        await app.settle()
        let session = try #require(app.measure)
        let expected = try await FakeKernel().shortestDistance(between: .edge(fixture.solid, a.id), and: .edge(fixture.solid, b.id))
        #expect(session.picks.count == 2)
        #expect(session.distance == expected)
        #expect(expected.distance > 1)
        let drawn = app.shownDimensions().filter { $0.id == OverlayDimensionID("measure/0") }
        #expect(drawn.count == 1)
        guard case .linear? = drawn.first?.geometry else { Issue.record("not linear"); return }
    }

    @Test func aThirdPickStartsANewMeasurement() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let edges = fixture.verticals
        for edge in edges.prefix(3) { fixture.click(fixture.target(edge)) }
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.picks.count == 1 && session.distance == nil)
        #expect(session.picks.first.map { if case .edge(_, let id) = $0 { id == edges[2].id } else { false } } == true)
    }

    @Test func clickingAPickAgainRemovesIt() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let (a, b) = (fixture.verticals[0], fixture.verticals[1])
        fixture.click(fixture.target(a))
        fixture.click(fixture.target(b))
        fixture.click(fixture.target(a))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.picks.count == 1 && session.distance == nil && !session.isMeasuring)
    }

    @Test func anEmptyClickClears() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        let session = try #require(fixture.app.measure)
        #expect(session.clickedModel(nil, at: ScreenPoint(5, 5), modifiers: [], projector: fixture.projector))
        #expect(session.picks.isEmpty && session.readings.isEmpty)
    }

    @Test func aStaleDistanceIsDropped() async throws {
        let kernel = FakeKernel()
        let gate = FirstCallGate()
        await kernel.setMeasureHook { gate.enter() }
        let fixture = await MeasureAppFixture.open(kernel: kernel)
        fixture.app.setMeasure(true)
        let edges = fixture.verticals
        fixture.click(fixture.target(edges[0]))
        fixture.click(fixture.target(edges[1]))
        // The first pair is held in the kernel; a new pair replaces it.
        fixture.click(fixture.target(edges[1]))
        fixture.click(fixture.target(edges[2]))
        gate.release()
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        let expected = try await FakeKernel().shortestDistance(between: .edge(fixture.solid, edges[0].id),
                                                               and: .edge(fixture.solid, edges[2].id))
        let stale = try await FakeKernel().shortestDistance(between: .edge(fixture.solid, edges[0].id),
                                                            and: .edge(fixture.solid, edges[1].id))
        #expect(expected != stale)
        #expect(session.distance == expected)
        #expect(!session.isMeasuring)
    }

    @Test func aRefusedDistanceShowsTheKernelsWords() async throws {
        let kernel = FakeKernel()
        await kernel.setMeasureHook { throw KernelError.invalidInput("Those can't be measured.") }
        let fixture = await MeasureAppFixture.open(kernel: kernel)
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        fixture.click(fixture.target(fixture.verticals[1]))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        #expect(session.problem == KernelError.invalidInput("Those can't be measured.").userMessage)
        #expect(session.distance == nil && !session.isMeasuring)
    }

    @Test func meshItemsAreNotPicked() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let mesh = DisplayMesh(positions: [.zero, .unitX, .unitY], normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2],
                               triangleFaces: [FaceID(0)], edgePolylines: [:])
        fixture.app.viewport.show([ViewportItem(solid: Solid(displaying: mesh))])
        await fixture.app.viewport.waitForMeshes()
        let session = try #require(fixture.app.measure)
        #expect(session.clickedModel(.face(solid: 0, FaceID(0)), at: ScreenPoint(5, 5), modifiers: [], projector: fixture.projector))
        #expect(session.clickedModel(.edge(solid: 3, EdgeID(0)), at: ScreenPoint(5, 5), modifiers: [], projector: fixture.projector))
        #expect(session.picks.isEmpty)
    }

    @Test func ghostsAreNotPicked() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.app.viewport.show([ViewportItem(solid: fixture.solid, isGhost: true)])
        await fixture.app.viewport.waitForMeshes()
        fixture.click(fixture.target(fixture.verticals[0]))
        #expect(fixture.app.measure?.picks.isEmpty == true)
    }

    @Test func aClickOnItemsThatLandedBeforeTheRefreshMeasuresNothingStale() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let edge = fixture.verticals[0]
        let other = Solid(displaying: DisplayMesh(positions: [.zero, .unitX, .unitY], normals: [.unitZ, .unitZ, .unitZ],
                                                  indices: [0, 1, 2], triangleFaces: [FaceID(0)], edgePolylines: [:]))
        for items in [[ViewportItem](), [ViewportItem(solid: other)]] {
            fixture.app.viewport.show(items)
            await fixture.app.viewport.waitForMeshes()
            #expect(session.clickedModel(fixture.target(edge), at: ScreenPoint(5, 5), modifiers: [], projector: fixture.projector))
            #expect(session.picks.isEmpty)
        }
    }

    @Test func hoverShowsTheEdgeAndSnapsToACorner() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let edge = fixture.verticals[0]
        let target = fixture.target(edge)
        session.hoverChanged(target, at: fixture.middle(of: target), projector: fixture.projector)
        #expect(session.overlay.lines.contains { $0.tint == .hovered })
        let ends = try #require(edge.curve?.ends)
        let nearEnd = fixture.screen(ends[0])
        // The pointer moving along the same edge hears nothing from the viewport's hover: the snap follows `pointerMoved`.
        session.pointerMoved(to: ScreenPoint(nearEnd.x + 3, nearEnd.y + 3), modifiers: [], projector: fixture.projector)
        let point = try #require(session.overlay.points.first { $0.tint == .hovered })
        #expect((point.position - ends[0]).length < 1e-9)
        session.pointerMoved(to: fixture.middle(of: target), modifiers: [], projector: fixture.projector)
        #expect(session.overlay.points.isEmpty && !session.overlay.lines.isEmpty)
    }

    @Test func aCornerIsPickedAtTheEdgesEnd() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let edge = fixture.verticals[0]
        let ends = try #require(edge.curve?.ends)
        fixture.click(fixture.target(edge), at: fixture.screen(ends[1]))
        guard case let .corner(_, id, _, at)? = fixture.app.measure?.picks.first else { Issue.record("not a corner"); return }
        #expect(id == edge.id && (at - ends[1]).length < 1e-9)
        #expect(fixture.app.measure?.overlay.points.contains { $0.tint == .selected } == true)
    }

    @Test func newSolidsClearTheMeasurement() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        fixture.click(fixture.target(fixture.verticals[1]))
        await fixture.app.settle()
        try fixture.app.document.perform(.setInput(fixture.box.extrude.id, "distance", .number(25)),
                                         name: UndoName.changeInput("Distance"))
        await fixture.app.settle()
        await fixture.app.settle()
        #expect(fixture.app.measure != nil)
        #expect(fixture.app.measure?.picks.isEmpty == true && fixture.app.measure?.distance == nil)
    }
}

@MainActor
struct MeasureSceneChangeTests {
    private func other(_ fixture: MeasureAppFixture) async throws -> Solid {
        try await fixture.kernel.extrude(.rectangle(width: 3, height: 3, plane: .xy), distance: 3, mode: .oneSided,
                                         tag: NodeTag(node: NodeID(), item: 0))
    }

    @Test func aMeasurementSurvivesChangesToOtherItemsAndClearsWhenAPickedPartChanges() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        fixture.click(fixture.target(fixture.verticals[0]))
        fixture.click(fixture.target(fixture.verticals[1]))
        await fixture.app.settle()
        let session = try #require(fixture.app.measure)
        let picked = ViewportItem(solid: fixture.solid)
        session.sceneChanged([picked, ViewportItem(solid: try await other(fixture))])
        session.sceneChanged([picked, ViewportItem(solid: try await other(fixture))])
        #expect(session.picks.count == 2 && session.distance != nil)
        session.sceneChanged([picked])
        #expect(session.picks.count == 2 && session.distance != nil)
        #expect(!session.dimensions(style: fixture.app.viewport.dimensionStyle, units: DocumentUnits()).isEmpty)
        session.sceneChanged([ViewportItem(solid: try await other(fixture))])
        #expect(session.picks.isEmpty && session.distance == nil)
    }

    @Test func hoverSurvivesASceneChange() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let target = fixture.target(fixture.verticals[0])
        fixture.app.viewport.hovered = target
        session.sceneChanged([ViewportItem(solid: fixture.solid)])
        session.pointerMoved(to: fixture.middle(of: target), modifiers: [], projector: fixture.projector)
        #expect(session.overlay.lines.contains { $0.tint == .hovered })
    }
}
