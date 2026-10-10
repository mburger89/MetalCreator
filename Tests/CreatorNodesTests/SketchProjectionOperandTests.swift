import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorNodes
import Testing

/// A Sketch projection of a hole's rim through a face a union merged (roadmap "Naming: face picks on merged
/// faces"): `SketchProjections.locate` finds the rim by operand and says when it had to guess between two.
struct SketchProjectionOperandTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    /// The plate's side (face 0) with its rim (edge 0); with `flangeRim`, a flange face (face 1) has one too (edge 1).
    func reference(flangeRim: Bool) -> Solid {
        func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitY, length: 5, midpoint: Vector3(-30, 16, z),
                     convexity: .concave, faces: [FaceID(face), FaceID(2)],
                     curve: .line(start: Vector3(-30, 14, z), end: Vector3(-30, 18, z)))
        }
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        let topology = Topology(faces: faces, edges: flangeRim ? [rim(0, 0, at: 3), rim(1, 1, at: 12)] : [rim(0, 0, at: 3)])
        return Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    var pick: EdgePick { EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1) }

    @Test func aRimOnTheOperandThatIsLeftIsFoundWithoutDrift() throws {
        guard case .found(let edge, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference(flangeRim: false)]) else {
            Issue.record("the rim wasn't found")
            return
        }
        #expect(edge.id == EdgeID(0))
        #expect(drift == nil)
    }

    @Test func aGuessBetweenTwoOperandsIsSaid() throws {
        guard case .found(_, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference(flangeRim: true)]) else {
            Issue.record("a rim wasn't found")
            return
        }
        #expect(drift == EdgeTagMatch.ambiguousPick)
    }
}
