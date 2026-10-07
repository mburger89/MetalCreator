// Test fixture file: kernel factory and topology helpers shared by the conformance suites.
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorOCCT

/// Every kernel the conformance suite runs against. A future pure-Swift kernel is added here.
enum KernelUnderTest: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case occt

    func make() -> any Kernel {
        switch self {
        case .occt: OCCTKernel()
        }
    }

    var testDescription: String { rawValue }
}

func newTag(item: Int = 0) -> NodeTag { NodeTag(node: NodeID(), item: item) }

/// A `width` × `depth` × `height` box from a centred rectangle on XY, extruded up from z = 0.
func box(_ kernel: any Kernel, _ width: Double, _ depth: Double, _ height: Double, tag: NodeTag = newTag()) async throws -> Solid {
    try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided, tag: tag)
}

func hasTag(_ face: FaceInfo, _ role: TopoRole, of tag: NodeTag) -> Bool {
    face.tags.contains(TopoTag(tag, role))
}

func faces(_ solid: Solid, role: TopoRole, of tag: NodeTag) -> [FaceInfo] {
    solid.topology.faces.filter { hasTag($0, role, of: tag) }
}

/// Edges whose two adjacent faces satisfy `a` and `b` (in either order). Seams excluded.
func edges(_ solid: Solid, between a: (FaceInfo) -> Bool, and b: (FaceInfo) -> Bool) -> [EdgeInfo] {
    solid.topology.edges.filter { edge in
        guard !edge.isSeam, edge.faces.count == 2,
              let first = solid.topology.face(edge.faces[0]), let second = solid.topology.face(edge.faces[1]) else { return false }
        return (a(first) && b(second)) || (a(second) && b(first))
    }
}
