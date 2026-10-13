// Test fixture file: a kernel that answers distances (all zero) after cancelling the task that asked.
import CreatorGeometry
import CreatorKernel
import Foundation

/// Cancels the calling task from inside `distances` and then answers, so a test can cancel a sampling in the middle of a batch:
/// the kernel itself never throws, so whatever stops the sampling afterwards is the sampler's own check. Nothing else is supported.
actor CancellingDistanceKernel: Kernel {
    private(set) var calls = 0

    func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double] {
        calls += 1
        withUnsafeCurrentTask { $0?.cancel() }
        return [Double](repeating: 0, count: points.count)
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

    func place(_ tools: [Solid], at transforms: [Transform], qualifying qualify: @Sendable (NodeID) -> NodeID,
               tag: NodeTag) throws -> [Solid] {
        throw KernelError.unsupported("place")
    }

    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("fillet")
    }

    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        throw KernelError.unsupported("chamfer")
    }

    func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        throw KernelError.unsupported("tessellate")
    }

    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        throw KernelError.unsupported("export")
    }

    func properties(of solid: Solid) throws -> SolidProperties {
        throw KernelError.unsupported("properties")
    }
}
