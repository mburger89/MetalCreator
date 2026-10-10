import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch
import Testing
@testable import CreatorNodes

/// A sketch's projected edges re-resolved the way the node does on every evaluation, for the editor to draw.
struct SketchRefreshTests {
    func box() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 40, height: 20, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }

    func sketch() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xy))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(1, 0))))))
        return sketch
    }

    func source(_ sketch: Sketch) -> ProjectionSource? {
        for id in sketch.entityIDs {
            if case .projected(let source)? = sketch.entities[id]?.kind { return source }
        }
        return nil
    }

    @Test func aProjectionTakesTheEdgesCurrentCurve() async throws {
        let solid = try await box()
        let settings: [SocketName: ConstantValue] = [NodeSetting.projection("edge1"): .edgePicks(solid.topology.picks(for: [EdgeID(1)]))]
        let refreshed = SketchNode.refreshingProjections(of: sketch(), settings: settings, references: [solid], on: .xy)
        let edge = try #require(solid.topology.edge(EdgeID(1)))
        guard case .curve(let expected) = EdgeProjection.project(edge, onto: .xy) else {
            Issue.record("the top edge projects onto xy")
            return
        }
        #expect(source(refreshed) == ProjectionSource(reference: "edge1", curve: expected), "the stale unit line is replaced")
    }

    @Test func aPickThatFindsNoEdgeSuspendsTheProjectionAndKeepsItsLastCurve() async throws {
        let solid = try await box()
        let refreshed = SketchNode.refreshingProjections(of: sketch(), settings: [:], references: [solid], on: .xy)
        #expect(source(refreshed)?.isSuspended == true)
        #expect(source(refreshed)?.curve == .line(.zero, Vector2(1, 0)))
        let nothing = SketchNode.refreshingProjections(of: sketch(), settings: [:], references: [], on: .xy)
        #expect(source(nothing)?.isSuspended == true, "no reference solid: suspended too")
    }
}
