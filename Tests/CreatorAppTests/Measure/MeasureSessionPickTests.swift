import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The Measure tool's section outlines, mesh points and kept measurements (measure part B).
@MainActor
struct MeasureSessionPickTests {
    @Test func aClickNearASectionOutlinePicksIt() async throws {
        let (fixture, outline) = try await sectioned()
        fixture.click(nil, at: ScreenPoint(outline.x + 3, outline.y))
        guard case .sectionEdge? = fixture.app.measure?.picks.first else { Issue.record("not a section edge"); return }
        #expect(fixture.app.measure?.anchors.count == 1)
    }

    @Test func theSectionOutlineWinsOverTheFaceBehind() async throws {
        let (fixture, outline) = try await sectioned()
        let face = try #require(fixture.solid.topology.faces.first)
        fixture.click(.face(solid: 0, face.id), at: outline)
        guard case .sectionEdge? = fixture.app.measure?.picks.first else { Issue.record("not a section edge"); return }
        #expect(fixture.app.measure?.picks.count == 1)
    }

    @Test func turningTheSectionOffLosesASectionEdgePick() async throws {
        let (fixture, outline) = try await sectioned()
        fixture.click(nil, at: outline)
        let session = try #require(fixture.app.measure)
        #expect(session.picks.count == 1 && !session.isLost)
        fixture.app.setSection(false)
        await fixture.app.settle()
        #expect(session.isLost && session.picks.isEmpty && session.anchors.count == 1)
    }

    @Test func aClickOnAMeshPicksItsSurfacePoint() async throws {
        let (fixture, session) = try await meshFixture()
        let point = ScreenPoint(700, 450)
        #expect(session.clickedModel(.face(solid: 0, FaceID(0)), at: point, modifiers: [], projector: fixture.projector))
        let expected = try #require(fixture.app.viewport.surfacePoint(at: point, solidIndex: 0))
        guard case let .meshPoint(solid, at)? = session.picks.first else { Issue.record("not a mesh point"); return }
        #expect(solid == 0 && (at - expected).length < 1e-9)
        #expect(session.anchors == [.meshPoint(expected)])
    }

    @Test func hoverOverAMeshShowsNothing() async throws {
        let (fixture, session) = try await meshFixture()
        let target = PickTarget.face(solid: 0, FaceID(0))
        session.hoverChanged(target, at: ScreenPoint(700, 450), projector: fixture.projector)
        session.pointerMoved(to: ScreenPoint(700, 450), modifiers: [], projector: fixture.projector)
        #expect(session.hover == nil && session.overlay.points.isEmpty && session.overlay.lines.isEmpty)
    }

    @Test func aThirdClickKeepsThePairAndStartsAgain() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        var kept: [KeptMeasurement] = []
        session.keep = { kept.append($0) }
        for edge in fixture.verticals.prefix(3) { fixture.click(fixture.target(edge)) }
        await fixture.app.settle()
        #expect(kept.count == 1 && kept[0].anchors.count == 2)
        #expect(session.picks.count == 1 && session.anchors.count == 1)
    }

    @Test func keepCurrentKeepsOnePick() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        var kept: [KeptMeasurement] = []
        session.keep = { kept.append($0) }
        session.keepCurrent()
        #expect(kept.isEmpty, "nothing picked, nothing kept")
        fixture.click(fixture.target(fixture.verticals[0]))
        session.keepCurrent()
        #expect(kept.count == 1 && kept[0].anchors.count == 1)
        #expect(session.picks.isEmpty && session.anchors.isEmpty)
    }

    /// The box with the section on and Measure running, and a point on the screen on one of the section's outlines.
    private func sectioned() async throws -> (MeasureAppFixture, ScreenPoint) {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setSection(true)
        await fixture.app.settle()
        fixture.app.setMeasure(true)
        let piece = try #require(fixture.app.sectionCaps.parts.first?.section.pieces.first { $0.sourceFace != nil })
        return (fixture, fixture.screen(MeasureResolver.midpoint(of: piece)))
    }

    /// A mesh item big enough to cover the middle of the view, with Measure running over it.
    private func meshFixture() async throws -> (MeasureAppFixture, MeasureSession) {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let mesh = DisplayMesh(positions: [Vector3(-500, -500, 0), Vector3(500, -500, 0), Vector3(0, 500, 0)],
                               normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2], triangleFaces: [FaceID(0)],
                               edgePolylines: [:])
        fixture.app.viewport.show([ViewportItem(solid: Solid(displaying: mesh))])
        await fixture.app.viewport.waitForMeshes()
        let session = try #require(fixture.app.measure)
        session.sceneChanged(fixture.app.measureScene())
        return (fixture, session)
    }
}
