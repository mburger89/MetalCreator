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
        let (fixture, outline, normal) = try await sectioned()
        fixture.click(nil, at: ScreenPoint(outline.x + 3 * normal.x, outline.y + 3 * normal.y))
        guard case .sectionEdge? = fixture.app.measure?.picks.first else { Issue.record("not a section edge"); return }
        #expect(fixture.app.measure?.anchors.count == 1)
    }

    @Test func aClickBeyondTheOutlineToleranceDoesNotPickIt() async throws {
        let (fixture, outline, normal) = try await sectioned()
        fixture.click(nil, at: ScreenPoint(outline.x + 10 * normal.x, outline.y + 10 * normal.y))
        #expect(fixture.app.measure?.picks.isEmpty == true)
    }

    @Test func theSectionOutlineWinsOverTheFaceBehind() async throws {
        let (fixture, outline, _) = try await sectioned()
        let face = try #require(fixture.solid.topology.faces.first)
        fixture.click(.face(solid: 0, face.id), at: outline)
        guard case .sectionEdge? = fixture.app.measure?.picks.first else { Issue.record("not a section edge"); return }
        #expect(fixture.app.measure?.picks.count == 1)
    }

    @Test func turningTheSectionOffLosesASectionEdgePick() async throws {
        let (fixture, outline, _) = try await sectioned()
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
        // Not vacuous: the same hover over the box's edge does show one.
        let box = await MeasureAppFixture.open()
        box.app.setMeasure(true)
        let boxSession = try #require(box.app.measure)
        let edge = box.target(box.verticals[0])
        boxSession.hoverChanged(edge, at: box.middle(of: edge), projector: box.projector)
        #expect(boxSession.hover != nil)
    }

    @Test func theSameFaceOnTwoPartsMeasuresBetweenThem() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let box = fixture.solid
        let twin = try await fixture.kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                    tag: NodeTag(node: fixture.box.extrude.id, item: 0))
        fixture.app.viewport.show([ViewportItem(solid: box), ViewportItem(solid: twin)])
        await fixture.app.viewport.waitForMeshes()
        session.sceneChanged(fixture.app.measureScene())
        let face = try #require(box.topology.faces.first { ($0.normal?.z ?? 0) > 0.5 }).id
        #expect(session.clickedModel(.face(solid: 1, face), at: ScreenPoint(700, 450), modifiers: [], projector: fixture.projector))
        #expect(session.clickedModel(.face(solid: 0, face), at: ScreenPoint(700, 450), modifiers: [], projector: fixture.projector))
        #expect(session.anchors.count == 2)
        #expect(session.picks.map(\.solidIndex) == [1, 0])
        await session.waitForDistance()
        #expect(session.distance != nil || session.isMeasuring || session.problem != nil)
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

    @Test func aClickWhileLostDropsTheLostAnchor() async throws {
        let (fixture, session, kept) = try await lostFixture()
        fixture.click(fixture.target(fixture.verticals[2]))
        #expect(!session.isLost && session.anchors.count == 2 && kept.items.isEmpty)
        #expect(session.picks.count == 2)
        guard case let .edge(_, id)? = session.picks.first else { Issue.record("not an edge"); return }
        #expect(id == fixture.verticals[0].id)
    }

    @Test func keepCurrentDoesNothingWhileLost() async throws {
        let (_, session, kept) = try await lostFixture()
        session.keepCurrent()
        #expect(kept.items.isEmpty && session.anchors.count == 2 && session.isLost)
    }

    final class Kept { var items: [KeptMeasurement] = [] }

    /// An edge of the box and a point of a mesh are picked, then the mesh leaves the scene: the point's anchor is lost.
    private func lostFixture() async throws -> (MeasureAppFixture, MeasureSession, Kept) {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let kept = Kept()
        session.keep = { kept.items.append($0) }
        let box = fixture.solid
        let mesh = DisplayMesh(positions: [Vector3(-500, -500, 0), Vector3(500, -500, 0), Vector3(0, 500, 0)],
                               normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2], triangleFaces: [FaceID(0)],
                               edgePolylines: [:])
        fixture.app.viewport.show([ViewportItem(solid: box), ViewportItem(solid: Solid(displaying: mesh))])
        await fixture.app.viewport.waitForMeshes()
        session.sceneChanged(fixture.app.measureScene())
        fixture.click(fixture.target(fixture.verticals[0]))
        #expect(session.clickedModel(.face(solid: 1, FaceID(0)), at: ScreenPoint(700, 450), modifiers: [],
                                     projector: fixture.projector))
        #expect(session.anchors.count == 2)
        session.sceneChanged(MeasureSceneChangeTests.scene([box]))
        #expect(session.isLost && session.anchors.count == 2)
        return (fixture, session, kept)
    }

    /// The box with the section on and Measure running, a point on the screen on one of the section's outlines, and the unit
    /// direction on screen perpendicular to that piece.
    private func sectioned() async throws -> (MeasureAppFixture, ScreenPoint, ScreenPoint) {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setSection(true)
        await fixture.app.settle()
        fixture.app.setMeasure(true)
        let piece = try #require(fixture.app.sectionCaps.parts.first?.section.pieces.first { $0.sourceFace != nil })
        let (first, last) = (fixture.screen(try #require(piece.polyline.first)), fixture.screen(try #require(piece.polyline.last)))
        let length = ((last.x - first.x) * (last.x - first.x) + (last.y - first.y) * (last.y - first.y)).squareRoot()
        let normal = ScreenPoint(-(last.y - first.y) / length, (last.x - first.x) / length)
        return (fixture, fixture.screen(MeasureResolver.midpoint(of: piece)), normal)
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
