import CreatorGeometry

/// Drain holes (implicit spec §3.6, §4.6): where the enclosed voids of an implicit solid are, and the solid with a round hole drilled
/// from each of them to the outside.
public enum DrainHoles {
    /// The lowest point of each enclosed void of `solid` along `direction` (the cell centre farthest in that direction, the middle one
    /// of those in the lowest layer), one per void, in the order of the voids. The voids are found on the coarse grid of the
    /// trapped-volume check, evaluated on the implicit itself.
    /// - Throws: `ImplicitMeshingError.empty` for a solid with no finite bounds, and `CancellationError`.
    public static func drainPoints(of solid: ImplicitSolid, direction: Vector3,
                                   using evaluator: any ImplicitBatchEvaluator) async throws -> [Vector3] {
        let grid = try await OccupancyGrid.of(solid, using: evaluator)
        return try lowestPoints(of: grid, direction: direction)
    }

    /// The lowest point of each enclosed void of `grid`. Kept out of the async function above: the Windows 6.4 toolchain asserts in its
    /// coroutine splitting (`CoroFrame.cpp`) when the loop's locals live in the async frame.
    private static func lowestPoints(of grid: OccupancyGrid, direction: Vector3) throws -> [Vector3] {
        let found = try EnclosedVoids(grid)
        return found.voids.map { cells in
            let centres = cells.map { grid.center(of: Int($0)) }
            // Cells in the lowest layer tie; the one nearest their middle is where the hole goes.
            let lowest = centres.map { $0.dot(direction) }.max() ?? 0
            let layer = centres.filter { $0.dot(direction) >= lowest - 1e-9 }
            let middle = layer.reduce(Vector3.zero, +) * (1.0 / Double(layer.count))
            return layer.min { ($0 - middle).length < ($1 - middle).length } ?? centres[0]
        }
    }

    /// Whether `solid` has a box of finite size: a hole's length comes from it, so a solid without one can't be drilled.
    public static func hasFiniteBounds(_ solid: ImplicitSolid) -> Bool {
        let size = solid.bounds.size
        return size.x.isFinite && size.y.isFinite && size.z.isFinite
    }

    /// `solid` with a cylinder of `diameter` taken out of it at each of `points`, running from the point along `direction` until it
    /// has left the solid's box. `solid` itself when there are no points, `direction` has no length or the box is not finite.
    public static func drilled(_ solid: ImplicitSolid, at points: [Vector3], diameter: Double, direction: Vector3) -> ImplicitSolid {
        guard !points.isEmpty, hasFiniteBounds(solid), let axis = direction.normalized else { return solid }
        let reach = solid.bounds.size.length + diameter
        let holes = points.map { point -> ImplicitSolid in
            let centre = point + axis * (reach / 2)
            return .moved(.cylinder(radius: diameter / 2, halfHeight: reach / 2), frame(at: centre, facing: axis))
        }
        return .subtract([solid] + holes, blend: .constant(0))
    }

    /// A frame at `origin` whose Z axis is `axis` (a unit vector).
    static func frame(at origin: Vector3, facing axis: Vector3) -> RigidMove {
        let helper: Vector3 = abs(axis.x) < 0.9 ? .unitX : .unitY
        let x = (helper - axis * helper.dot(axis)).normalized ?? .unitX
        return RigidMove(origin: origin, xAxis: x, yAxis: axis.cross(x), zAxis: axis)
    }
}
