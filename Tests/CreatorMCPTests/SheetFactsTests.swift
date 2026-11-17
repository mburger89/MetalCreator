import CreatorGeometry
import CreatorKernel
@testable import CreatorMCP
import Testing

private final class EmptyStorage: SolidStorage {
    let estimatedBytes = 0
}

/// NS-1 Task 9: the facts of a sheet and of a mixed body.
@MainActor struct SheetFactsTests {
    private func body(faces: [Bool], openEdges: Int, closedEdges: Int) -> Solid {
        let faceInfos = faces.enumerated().map { index, open in
            FaceInfo(id: FaceID(index), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [], isOnOpenShell: open)
        }
        func edge(_ id: Int, faceCount: Int) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .unknown,
                     faces: (0..<faceCount).map { FaceID($0) })
        }
        let edges = (0..<openEdges).map { edge($0, faceCount: 1) } + (0..<closedEdges).map { edge(openEdges + $0, faceCount: 2) }
        return Solid(topology: Topology(faces: faceInfos, edges: edges),
                     bounds: BoundingBox(min: .zero, max: Vector3(10, 20, 0)), storage: EmptyStorage())
    }

    @Test func aSheetSaysSheetAndCountsItsOpenEdges() {
        let sheet = body(faces: [true], openEdges: 4, closedEdges: 0)
        #expect(SolidFacts(sheet).text == "sheet: 1 face, 4 open edges, bounds (0, 0, 0) to (10, 20, 0) mm")
    }

    @Test func aMixedBodySaysSolidAndSheet() {
        let mixed = body(faces: [false, false, true], openEdges: 1, closedEdges: 3)
        #expect(SolidFacts(mixed).text == "solid and sheet: 3 faces, 1 open edge, bounds (0, 0, 0) to (10, 20, 0) mm")
    }

    @Test func aClosedSolidIsUnchanged() {
        let closed = body(faces: [false, false], openEdges: 0, closedEdges: 3)
        #expect(SolidFacts(closed).text == "solid: 2 faces, 3 edges, bounds (0, 0, 0) to (10, 20, 0) mm")
    }
}
