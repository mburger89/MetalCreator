import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The Measure tool's circle centres (a hole's centre is its own hover target, far from its rim), one vertex reached through two
/// edges, a measurement started during a load, an angle without a distance and a hover on a replaced solid.
@MainActor
struct MeasureSessionCentreTests {
    /// A cylinder of radius 20 shown alone, seen from above, with `radiusOnScreen` points between its centre and its rim.
    private struct Cylinder {
        var fixture: MeasureAppFixture
        var session: MeasureSession
        var projector: ViewportProjector
        var rim: EdgeInfo
        var top: FaceInfo
    }

    private func cylinder(radiusOnScreen: Double) async throws -> Cylinder {
        var builder = GraphBuilder()
        let circle = builder.add(CircleNode.self, ["diameter": .number(40)])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
        let output = builder.add(OutputNode.self)
        builder.wire(circle, "profile", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        let fixture = MeasureAppFixture(app: app, kernel: FakeKernel(), box: (circle, extrude, output))
        app.setMeasure(true)
        await app.settle()
        let session = try #require(app.measure)
        let solid = fixture.solid
        session.sceneChanged(app.measureScene())
        let size = ViewportSize(width: 1400, height: 900)
        func projector(distance: Double) -> ViewportProjector {
            ViewportProjector(pose: CameraPose(target: Vector3(0, 0, 10), distance: distance, pitch: .pi / 2,
                                               projection: .orthographic), size: size)
        }
        let probe = projector(distance: 100)
        let fitted = projector(distance: 100 * (20 / radiusOnScreen) / probe.millimetresPerPoint)
        let rim = try #require(solid.topology.edges.first { edge in
            if case let .circle(centre, _, _, _, _)? = edge.curve { abs(centre.z - 10) < 1e-9 } else { false }
        })
        let top = try #require(solid.topology.faces.first { ($0.normal?.z ?? 0) > 0.5 })
        return Cylinder(fixture: fixture, session: session, projector: fitted, rim: rim, top: top)
    }

    @Test func aLargeHoleCentreSnaps() async throws {
        let scene = try await cylinder(radiusOnScreen: 100)
        let (fixture, session, projector, rim, top) = (scene.fixture, scene.session, scene.projector, scene.rim, scene.top)
        defer { withExtendedLifetime(fixture) {} }
        let centre = try #require(projector.screenPoint(of: Vector3(0, 0, 10)))
        let rimPoint = try #require(projector.screenPoint(of: Vector3(20, 0, 10)))
        #expect(abs(rimPoint.x - centre.x) > 90, "the rim is far from the centre on screen")
        session.hoverChanged(.face(solid: 0, top.id), at: centre, projector: projector)
        guard case let .corner(0, _, .centre, at)? = session.hover else {
            Issue.record("no centre hover: \(String(describing: session.hover))")
            return
        }
        #expect((at - Vector3(0, 0, 10)).length < 1e-9 || (at - .zero).length < 1e-9)
        #expect(session.clickedModel(.face(solid: 0, top.id), at: centre, modifiers: [], projector: projector))
        guard case .corner(0, _, .centre, _)? = session.picks.first else { Issue.record("no centre pick"); return }
        // Away from the centre the rim and the face are still themselves.
        session.hoverChanged(.edge(solid: 0, rim.id), at: rimPoint, projector: projector)
        #expect(session.hover == .edge(solid: 0, rim.id), "\(String(describing: session.hover)) \(rimPoint)")
    }

    @Test func aSmallCircleStillPicksAsItsEdge() async throws {
        let scene = try await cylinder(radiusOnScreen: 8)
        let (fixture, session, projector, rim) = (scene.fixture, scene.session, scene.projector, scene.rim)
        defer { withExtendedLifetime(fixture) {} }
        let centre = try #require(projector.screenPoint(of: Vector3(0, 0, 10)))
        let rimPoint = try #require(projector.screenPoint(of: Vector3(20, 0, 10)))
        session.hoverChanged(.edge(solid: 0, rim.id), at: ScreenPoint(rimPoint.x - 3, rimPoint.y), projector: projector)
        #expect(session.hover == .edge(solid: 0, rim.id), "the centre is 5 points away but wins only within half the radius")
        #expect(session.clickedModel(.edge(solid: 0, rim.id), at: ScreenPoint(rimPoint.x - 3, rimPoint.y), modifiers: [],
                                     projector: projector))
        #expect(session.picks.first == .edge(solid: 0, rim.id))
        session.hoverChanged(nil, at: ScreenPoint(centre.x + 2, centre.y), projector: projector)
        guard case .corner(0, _, .centre, _)? = session.hover else { Issue.record("no centre within 4 points"); return }
    }

    @Test func oneVertexThroughTwoEdgesTogglesOff() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let edges = fixture.solid.topology.edges
        var found: (EdgeInfo, EdgeInfo, Vector3)?
        for first in edges {
            for second in edges where second.id != first.id {
                if let a = first.curve?.ends, let b = second.curve?.ends,
                   let shared = a.first(where: { p in b.contains { ($0 - p).length < 1e-9 } }) {
                    found = (first, second, shared)
                }
            }
            if found != nil { break }
        }
        let (first, second, vertex) = try #require(found)
        let at = fixture.screen(vertex)
        #expect(session.clickedModel(.edge(solid: 0, first.id), at: at, modifiers: [], projector: fixture.projector))
        guard case .corner? = session.picks.first else { Issue.record("not a corner"); return }
        #expect(session.clickedModel(.edge(solid: 0, second.id), at: at, modifiers: [], projector: fixture.projector))
        #expect(session.anchors.isEmpty && session.picks.isEmpty, "the same vertex toggles off")
    }

    @Test func measureStartedDuringALoadFollowsTheLoadedScene() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let twin = try await fixture.kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                    tag: NodeTag(node: fixture.box.extrude.id, item: 0))
        // A scene that lands after Measure began, with nothing else changing, reaches the session.
        fixture.app.viewport.show([ViewportItem(solid: twin)])
        for _ in 0..<5 { await Task.yield() }
        let edge = try #require(twin.topology.edges.first)
        #expect(session.clickedModel(.edge(solid: 0, edge.id), at: ScreenPoint(700, 450), modifiers: [], projector: fixture.projector))
        #expect(session.anchors.count == 1, "the session resolves against the loaded scene, not the one before")
    }

    @Test func aHoverOnAReplacedSolidIsDropped() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        let session = try #require(fixture.app.measure)
        let target = fixture.target(fixture.verticals[0])
        session.hoverChanged(target, at: fixture.middle(of: target), projector: fixture.projector)
        #expect(session.hover != nil)
        let replaced = try await fixture.kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                        tag: NodeTag(node: fixture.box.extrude.id, item: 0))
        session.sceneChanged(MeasureScene(solids: [replaced], pickable: [true], parts: [], plane: nil))
        #expect(session.hover == nil && session.overlay.lines.isEmpty && session.overlay.points.isEmpty)
    }
}
