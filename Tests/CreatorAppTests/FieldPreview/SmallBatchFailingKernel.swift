import CreatorGeometry
import CreatorKernel
import Foundation

/// A kernel that only measures distances (as each point's x, which is enough to sample), and refuses a batch smaller than
/// `minimum` points, so a test can make the tint (a mesh's few vertices) fail while the slice (a grid of many samples) succeeds.
actor SmallBatchFailingKernel: Kernel {
    private let minimum: Int

    init(minimum: Int) { self.minimum = minimum }

    func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid { throw unsupported }
    func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid { throw unsupported }
    func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid { throw unsupported }
    func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid { throw unsupported }
    func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid { throw unsupported }
    func place(_ tools: [Solid], at transforms: [Transform], qualifying qualify: @Sendable (NodeID) -> NodeID,
               tag: NodeTag) throws -> [Solid] { throw unsupported }
    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid { throw unsupported }
    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid { throw unsupported }
    func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh { throw unsupported }
    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws { throw unsupported }
    func properties(of solid: Solid) throws -> SolidProperties { throw unsupported }

    func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double] {
        if points.count < minimum { throw KernelError.invalidInput("The batch is too small.") }
        return points.map(\.x)
    }

    private var unsupported: KernelError { .unsupported("this test kernel only measures") }
}
