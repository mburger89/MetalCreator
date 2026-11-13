import CreatorGeometry
import CreatorKernel
@testable import CreatorMCP
import Testing

private final class EmptyStorage: SolidStorage {
    let estimatedBytes = 0
}

@MainActor struct SolidFactsTests {
    private func solid(faces: Int, edges: Int, min: Vector3, max: Vector3) -> Solid {
        let face = FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [])
        let edge = EdgeInfo(id: EdgeID(0), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .unknown, faces: [])
        let topology = Topology(faces: Array(repeating: face, count: faces), edges: Array(repeating: edge, count: edges))
        return Solid(topology: topology, bounds: BoundingBox(min: min, max: max), storage: EmptyStorage())
    }

    @Test func textPluralsAndRounding() {
        let box = solid(faces: 6, edges: 12, min: .zero, max: Vector3(60, 40, 5))
        #expect(SolidFacts(box).text == "solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm")
        let one = solid(faces: 1, edges: 1, min: Vector3(0.123456, 0, 0), max: Vector3(1, 1, 1))
        #expect(SolidFacts(one).text == "solid: 1 face, 1 edge, bounds (0.1235, 0, 0) to (1, 1, 1) mm")
        let empty = solid(faces: 0, edges: 0, min: Vector3(1, 1, 1), max: Vector3(-1, -1, -1))
        #expect(SolidFacts(empty).text == "solid: 0 faces, 0 edges, no bounds")
    }
}
