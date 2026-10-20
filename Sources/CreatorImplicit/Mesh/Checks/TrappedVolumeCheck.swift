import CreatorGeometry

/// Trapped volumes (implicit spec §4.6): a coarse occupancy grid of the mesh (0.5 mm cells, or 1/32 of the longest side if that is
/// finer), flood filled from outside. Empty cells the fill cannot reach, in pockets of more than one cell, are voids that cannot
/// drain. A triangle looks into a void when a void cell lies a little way from it along its normal, and is highlighted.
///
/// A cell is solid when it is within half a cell of the surface or inside the part. Inside is the mesh's generalized winding number
/// (at least ½), asked once per region of cells, not the sign of the nearest feature's normal: where a sheet meets a slab tangentially and
/// the mesh is coarser than the wedge between them, the mesh overlaps itself and that sign reads solid cells as empty, which made 103
/// phantom voids of the lightweight bracket (spec Errata M5, D18).
public enum TrappedVolumeCheck {
    public struct Result: Sendable {
        /// The number of enclosed voids.
        public var voidCount: Int
        /// The triangles that face into a void, in order.
        public var triangles: [Int]
        /// The edge of the grid's cells in millimetres, 0 for a mesh with no triangles. A hole or a void must be a few cells across to be
        /// seen, so a cell larger than `OccupancyGrid.largestCell` (a very large part) means smaller drain holes may not count.
        public var cell: Double = 0
    }

    /// - Throws: `MeshDistanceError.notClosed` when the mesh has no inside, and `CancellationError`.
    public static func run(_ mesh: TriangleMesh) throws -> Result {
        guard let bounds = mesh.bounds, mesh.triangleCount > 0 else { return Result(voidCount: 0, triangles: []) }
        let positions = (0..<mesh.vertexCount).map { mesh.point($0) }
        let distances = try SignedDistanceMesh(positions: positions, indices: mesh.triangles)
        let (grid, found) = try findVoids(in: distances, bounds: bounds)
        guard !found.voids.isEmpty else { return Result(voidCount: 0, triangles: [], cell: grid.cell) }
        var facing: [Int] = []
        for index in 0..<mesh.triangleCount {
            if index & 0xFFF == 0 { try Task.checkCancellation() }
            let (a, b, c) = mesh.corners(of: index)
            guard let normal = (b - a).cross(c - a).normalized else { continue }
            let centre = (a + b + c) * (1.0 / 3)
            // The cells next to the surface count as solid, so look a cell or two out.
            let looksIn = [0.75, 1.25, 1.75].contains { reach in
                grid.index(containing: centre + normal * (reach * grid.cell)).map { found.label[$0] >= 0 } ?? false
            }
            if looksIn { facing.append(index) }
        }
        return Result(voidCount: found.voids.count, triangles: facing, cell: grid.cell)
    }

    /// The occupancy grid of the mesh and its enclosed voids. Only the cells within half a cell of the surface are solid in the grid (the
    /// distances are unsigned); `EnclosedVoids` decides which of the regions of cells farther away are inside the part, by the winding
    /// number, which a mesh that folds over itself cannot fool (Errata D18).
    static func findVoids(in distances: SignedDistanceMesh, bounds: BoundingBox) throws -> (grid: OccupancyGrid, found: EnclosedVoids) {
        var grid = OccupancyGrid(bounds: bounds)
        try grid.fill { points in points.map { distances.unsignedDistance(at: $0) } }
        return (grid, try EnclosedVoids(grid, isInside: { distances.isInside($0) }))
    }
}
