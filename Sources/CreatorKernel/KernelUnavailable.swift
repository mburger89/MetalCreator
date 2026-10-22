import CreatorGeometry
import Foundation

/// The kernel of a build with no OpenCascade (Linux and Windows in xp-1; since xp-2 the app uses `OCCTKernel` everywhere, and
/// this stays for tests of how the editor behaves without geometry): every operation answers
/// `KernelError.unavailable`, so a node that needs geometry shows "Geometry isn't available on this platform yet." on its
/// badge, while the graph, the inspector, the sketcher, patterns, groups, comments, saving and opening all work.
public actor KernelUnavailable: Kernel {
    public init() {}

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func place(_ tools: [Solid], at transforms: [Transform], qualifying qualify: @Sendable (NodeID) -> NodeID,
                      tag: NodeTag) throws -> [Solid] {
        try refuse()
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try refuse()
    }

    public func meshToSolid(positions: [SIMD3<Float>], triangles: [UInt32], tag: NodeTag) throws -> Solid {
        try refuse()
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try refuse()
    }

    public func properties(of solid: Solid) throws -> SolidProperties {
        try refuse()
    }

    public func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double] {
        try refuse()
    }

    public func faceParametrization(of face: FaceID, in solid: Solid) throws -> FaceParametrization {
        try refuse()
    }

    public func faceCoordinates(of points: [Vector3], on face: FaceID, in solid: Solid) throws -> [FaceSample] {
        try refuse()
    }

    /// Checks for cancellation on entry, as every kernel does, then refuses.
    private func refuse() throws -> Never {
        try Task.checkCancellation()
        throw KernelError.unavailable
    }
}
