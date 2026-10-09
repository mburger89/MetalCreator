import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorNodes
import Testing

/// A Sketch projection's pick drifts as an Edges by Tag pick does (roadmap "Naming: picks on merged faces"):
/// `SketchProjections.locate` adds up edges and runs across the references and asks `EdgePick.hasDrifted`.
struct SketchProjectionRunTests {
    let box = NodeID()
    var top: TopoTag { TopoTag(node: box, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: box, item: 0, role: .side(segment: 0)) }

    /// A reference whose only edge between `top` and `side` is one whole line, 32 mm long.
    var reference: Solid {
        let start = Vector3(-30, 16, 6)
        let end = Vector3(-30, -16, 6)
        let edge = EdgeInfo(id: EdgeID(0), kind: .line, direction: (end - start).normalized, length: 32,
                            midpoint: (start + end) * 0.5, convexity: .convex, faces: [FaceID(0), FaceID(1)],
                            curve: .line(start: start, end: end))
        let topology = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: [edge])
        return Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    func located(_ pick: EdgePick) -> (edge: EdgeID, drift: String?)? {
        guard case .found(let edge, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference]) else {
            return nil
        }
        return (edge.id, drift)
    }

    /// Picked while an operation split the edge in two (2 edges in 1 run), projected now that it is whole.
    @Test func aSplitEdgeThatIsWholeAgainIsFoundWithoutDrift() throws {
        let found = try #require(located(EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)))
        #expect(found.edge == EdgeID(0))
        #expect(found.drift == nil)
    }

    /// Picked as 2 edges in 2 runs, 1 now: drift, in Edges by Tag's words.
    @Test func fewerRunsThanRecordedIsDrift() throws {
        let found = try #require(located(EdgePick(key: EdgeKey([top], [side]), matchCount: 2)))
        #expect(found.edge == EdgeID(0))
        #expect(found.drift == "Matched 1 edge, expected 2.")
    }
}
