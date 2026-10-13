import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// The gate a test's meshes wait at, and how many meshes were asked for.
@MainActor
final class PreviewHarness {
    var gate: SamplingGate?
    private(set) var asked = 0
    var meshes: [ObjectIdentifier: DisplayMesh] = [:]

    @discardableResult
    func part(width: Double = 20, depth: Double = 10, height: Double = 6) async throws -> Solid {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        meshes[ObjectIdentifier(solid)] = try await kernel.tessellate(solid, tolerance: 0.05)
        return solid
    }

    func model(limit: Int = CoarseSampling.vertexLimit) -> FieldPreviewModel {
        FieldPreviewModel(kernel: FakeKernel(), distances: FieldDistanceCache(), vertexLimit: limit) { [self] solid in
            asked += 1
            if let gate { await gate.wait() }
            return meshes[ObjectIdentifier(solid)]
        }
    }

    func request(_ node: NodeID, _ field: Field, _ solids: [Solid], toEye: Vector3 = .unitZ) -> FieldPreviewRequest {
        FieldPreviewRequest(node: node, field: field, solids: solids, toEye: toEye)
    }
}
