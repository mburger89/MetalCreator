// Test fixture file: FakeKernel solids, a kernel that returns box meshes, and a bare solid storage.
import CreatorGeometry
import CreatorKernel
import Foundation

/// A FakeKernel box centred on the origin in x and y, standing on z = 0.
func fakeBox(width: Double = 10, depth: Double = 20, height: Double = 30, node: NodeID = NodeID()) async throws -> Solid {
    try await FakeKernel().extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided,
                                   tag: NodeTag(node: node, item: 0))
}

/// Tessellates any solid as `TestMeshes.box(solid.bounds)`, whose face and edge IDs match FakeKernel's prism. It
/// counts calls and honours the protocol's cancellation contract. With `failing`, every tessellation throws.
/// Nothing else is supported.
actor StubMeshKernel: Kernel {
    private(set) var tessellations = 0
    private var failing: Bool

    init(failing: Bool = false) {
        self.failing = failing
    }

    /// Makes later tessellations fail (or succeed again).
    func setFailing(_ failing: Bool) {
        self.failing = failing
    }

    func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("extrude")
    }

    func revolve(_ profile: Profile2D, axis: Axis, angle: CreatorGeometry.Angle, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("revolve")
    }

    func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("loft")
    }

    func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("boolean")
    }

    func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("transform")
    }

    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("fillet")
    }

    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("chamfer")
    }

    func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        if failing { throw KernelError.operationFailed(operation: "tessellate", reason: "the mesh could not be built.") }
        tessellations += 1
        return TestMeshes.box(solid.bounds)
    }

    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        throw KernelError.unsupported("export")
    }

    func properties(of solid: Solid) throws -> SolidProperties {
        throw KernelError.unsupported("properties")
    }
}

/// Storage for hand-built solids in tests.
final class TestStorage: SolidStorage {
    var estimatedBytes: Int { 0 }
}
