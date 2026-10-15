import CreatorGeometry

/// The bricks an engine is asked to mesh (implicit spec Errata D13), as plain values: no GPU type, so any engine can take them.
///
/// The lattice is the `BrickPlan`'s: lattice point (i, j, k) is at `origin + (i, j, k) * resolution`, and brick (a, b, c) holds the
/// voxels from lattice point (8a, 8b, 8c) to (8a + 7, 8b + 7, 8c + 7), plus the shared layer of points to 8a + 8. Only the bricks listed
/// are meshed; the surface closes across their faces because every edge of the lattice has one vertex, whichever bricks reach it.
public struct BrickMeshRequest: Sendable, Equatable {
    /// The world position of lattice point (0, 0, 0), in millimetres.
    public var origin: SIMD3<Double>
    /// The voxel size in millimetres.
    public var resolution: Double
    /// Integer brick coordinates, as `BrickPlan.bricks` lists them (sorted by x, then y, then z, which an engine may rely on).
    public var bricks: [SIMD3<Int32>]
    /// Whether each vertex takes the Newton step towards f = 0 and gets its normal from the gradient (the mesher's `snap`).
    public var snap: Bool

    public init(origin: SIMD3<Double>, resolution: Double, bricks: [SIMD3<Int32>], snap: Bool) {
        self.origin = origin
        self.resolution = resolution
        self.bricks = bricks
        self.snap = snap
    }

    /// The request for every brick of `plan`.
    public init(plan: BrickPlan, snap: Bool) {
        self.init(origin: SIMD3(plan.origin.x, plan.origin.y, plan.origin.z), resolution: plan.resolution, bricks: plan.bricks,
                  snap: snap)
    }
}
