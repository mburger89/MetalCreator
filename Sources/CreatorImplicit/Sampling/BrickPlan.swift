import CreatorGeometry

/// The sparse octree over an implicit solid (implicit spec §4.2): which 8 × 8 × 8 bricks of voxels the surface can pass through.
///
/// The root is a cube of bricks that covers the solid's bounds padded by one voxel. Each cell evaluates the solid at its centre; when
/// |f| ÷ lipschitz is more than half the cell's diagonal the surface can't be inside (the value can't change that fast) and the cell
/// is pruned. Cells that don't touch the bounds are pruned without evaluating. What survives down to a single brick is a brick to
/// mesh. Memory and time follow the surface area, not the volume.
public struct BrickPlan: Sendable {
    /// Voxels along each side of a brick; a brick has this many plus one lattice points on a side (the last is shared).
    public static let brickSize = 8

    /// The world position of lattice point (0, 0, 0).
    public let origin: Vector3
    /// The voxel size in millimetres.
    public let resolution: Double
    /// How many bricks the padded bounds span on each axis.
    public let brickCounts: [Int]
    /// The bricks the surface can pass through, as integer brick coordinates, sorted by x, then y, then z.
    public let bricks: [SIMD3<Int32>]
    /// How many cells the octree evaluated, bricks and pruned cells together.
    public let evaluatedCells: Int

    /// The most points sent to the evaluator at once while pruning.
    static let batch = 1 << 20

    public static func build(for solid: ImplicitSolid, resolution: Double,
                             using evaluator: any ImplicitBatchEvaluator) async throws -> BrickPlan {
        precondition(resolution.isFinite && resolution > 0, "BrickPlan needs a positive, finite resolution")
        let size = brickSize
        let box = solid.bounds
        // Bounds that aren't finite (an empty intersection built from NaN, an unbounded region) hold nothing to mesh.
        guard [box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z].allSatisfy(\.isFinite) else {
            throw ImplicitMeshingError.empty
        }
        let origin = box.min - Vector3(resolution, resolution, resolution)
        let span = box.max + Vector3(resolution, resolution, resolution) - origin
        let counts = try brickCounts(span: span, resolution: resolution)
        let longest = counts.max() ?? 1
        var cellBricks = 1
        while cellBricks < longest { cellBricks *= 2 }
        let brickLength = resolution * Double(size)
        let lipschitz = solid.lipschitz
        let reachable = BoundingBox(min: box.min - Vector3(resolution, resolution, resolution),
                                    max: box.max + Vector3(resolution, resolution, resolution))

        var cells: [SIMD3<Int32>] = [.zero]
        var survivors: [SIMD3<Int32>] = []
        var evaluated = 0
        while !cells.isEmpty {
            try Task.checkCancellation()
            let length = brickLength * Double(cellBricks)
            // Cells that can't touch the bounds hold no surface.
            let touching = cells.filter { cell in
                let low = origin + Vector3(Double(cell.x), Double(cell.y), Double(cell.z)) * brickLength
                return low.x <= reachable.max.x && low.x + length >= reachable.min.x && low.y <= reachable.max.y
                    && low.y + length >= reachable.min.y && low.z <= reachable.max.z && low.z + length >= reachable.min.z
            }
            evaluated += touching.count
            let undecided = try await undecidedCells(touching, origin: origin, cellLength: length, brickLength: brickLength,
                                                     lipschitz: lipschitz, using: evaluator)
            if cellBricks == 1 {
                survivors += undecided
                break
            }
            let half = Int32(cellBricks / 2)
            cells = undecided.flatMap { cell in
                (0..<8).compactMap { child -> SIMD3<Int32>? in
                    let next = SIMD3(cell.x + (child & 1 == 0 ? 0 : half), cell.y + (child & 2 == 0 ? 0 : half),
                                     cell.z + (child & 4 == 0 ? 0 : half))
                    return Int(next.x) < counts[0] && Int(next.y) < counts[1] && Int(next.z) < counts[2] ? next : nil
                }
            }
            cellBricks /= 2
        }
        survivors.sort { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
        return BrickPlan(origin: origin, resolution: resolution, brickCounts: counts, bricks: survivors, evaluatedCells: evaluated)
    }

    /// How many bricks cover `span` on each axis. A grid too large to index is refused like an over-budget job (`Int(_:)` would trap).
    private static func brickCounts(span: Vector3, resolution: Double) throws -> [Int] {
        try [span.x, span.y, span.z].map { extent in
            let bricks = (extent / (resolution * Double(brickSize))).rounded(.up)
            guard bricks.isFinite, bricks < Double(1 << 30) else {
                throw ImplicitMeshingError.tooBig(bytes: Int.max / 2, resolution: resolution, suggestion: resolution * 2)
            }
            return max(1, Int(bricks))
        }
    }

    /// The cells whose centre value can't rule the surface out: |f| ÷ lipschitz is not more than half the cell's diagonal.
    private static func undecidedCells(_ cells: [SIMD3<Int32>], origin: Vector3, cellLength length: Double, brickLength: Double,
                                       lipschitz: Double, using evaluator: any ImplicitBatchEvaluator) async throws -> [SIMD3<Int32>] {
        var undecided: [SIMD3<Int32>] = []
        let halfDiagonal = length * 3.0.squareRoot() / 2
        for start in stride(from: 0, to: cells.count, by: batch) {
            let slice = Array(cells[start..<min(start + batch, cells.count)])
            let centres = slice.map { cell -> SIMD3<Float> in
                let centre = origin + (Vector3(Double(cell.x), Double(cell.y), Double(cell.z)) * brickLength)
                    + Vector3(length / 2, length / 2, length / 2)
                return SIMD3(Float(centre.x), Float(centre.y), Float(centre.z))
            }
            let values = try await evaluator.evaluate(centres)
            for (cell, value) in zip(slice, values) where !(Double(abs(value)) / lipschitz > halfDiagonal) {
                undecided.append(cell)
            }
        }
        return undecided
    }

    /// The world position of lattice point (i, j, k).
    public func point(_ i: Int, _ j: Int, _ k: Int) -> Vector3 {
        origin + Vector3(Double(i), Double(j), Double(k)) * resolution
    }

    /// The solid's value at the 9 × 9 × 9 lattice points of each brick in `bricks`, brick after brick, x fastest.
    public func samples(of bricks: ArraySlice<SIMD3<Int32>>, using evaluator: any ImplicitBatchEvaluator) async throws -> [Float] {
        let size = Self.brickSize
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(bricks.count * (size + 1) * (size + 1) * (size + 1))
        for brick in bricks {
            for z in 0...size {
                for y in 0...size {
                    for x in 0...size {
                        let p = point(Int(brick.x) * size + x, Int(brick.y) * size + y, Int(brick.z) * size + z)
                        points.append(SIMD3(Float(p.x), Float(p.y), Float(p.z)))
                    }
                }
            }
        }
        return try await evaluator.evaluate(points)
    }
}
