import CreatorGeometry

extension OccupancyGrid {
    /// The grid of an implicit solid, evaluated by `evaluator`: solid where the value is at most half a cell (the surface is that near,
    /// or the point is inside). Drain Holes runs the trapped-volume test on the implicit this way, with no mesh. The solid's own
    /// Lipschitz bound lets whole blocks of cells far from the surface be classified from one value.
    /// A solid whose bounds are not finite has no grid and throws `ImplicitMeshingError.empty`.
    /// - Throws: `ImplicitMeshingError.empty` and `CancellationError`.
    public static func of(_ solid: ImplicitSolid, using evaluator: any ImplicitBatchEvaluator) async throws -> OccupancyGrid {
        let box = solid.bounds
        guard [box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z].allSatisfy(\.isFinite) else {
            throw ImplicitMeshingError.empty
        }
        var grid = OccupancyGrid(bounds: box)
        try await grid.fill(lipschitz: solid.lipschitz, awaiting: { points in
            let values = try await evaluator.evaluate(points.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) })
            return values.map { Double($0) }
        })
        return grid
    }
}
