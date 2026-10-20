import CreatorGeometry

/// A coarse grid of cells over a part (implicit spec §4.6): which cells are solid, in the sense that matters for draining. A cell is
/// solid when its centre is inside the part or within half a cell of the surface, so a wall thinner than a cell is never a gap in the
/// grid, and a void or a channel has to be larger than about a cell to be seen. The grid has two empty cells of padding round the part, so
/// its corner is always outside.
///
/// How "inside" is decided depends on where the grid comes from (Errata D18). A solid's own field says it exactly, by its sign, so
/// `of(_:using:)` (Drain Holes) marks every cell the field puts at most half a cell out. A mesh has no field: `TrappedVolumeCheck` fills
/// the cells near the surface from the unsigned distance and `EnclosedVoids(_:isInside:)` asks the mesh's winding number about each
/// region of cells farther away. Both use the same definition of solid, but not the same grid (the implicit's bounds against the mesh's), so
/// they may disagree about a pocket a cell or two across.
public struct OccupancyGrid: Sendable {
    /// The most cells a grid may have, padding included. The flood fill holds `isSolid` and `reached` (a byte each), `label` (4 bytes),
    /// a stack that can reach 4 bytes a cell and the voids' cell lists, 4 more at worst (the outside is not listed): about 450 MB at
    /// the largest grid in the worst case, before the process's own. `ImplicitBench` i-7 measures the peak resident size of a 150 mm
    /// cube. A part that would need more gets coarser cells (`cellSize(forSize:)`): 0.5 mm holds up to a 150 mm cube; a 300 mm cube
    /// gets 1 mm cells and a metre cube 3 mm.
    public static let largestCellCount = 32_000_000

    /// The largest edge of a cell, in millimetres. The spec says 2 mm; a drain hole of the default 2 mm is then one cell across and
    /// the grid cannot see through it (the cell beside its wall is "within half a cell of the surface"), so the Check Trapped Volumes
    /// that follows Drain Holes would still report the void. A hole is seen when it is about four cells across: 0.5 mm.
    public static let largestCell = 0.5

    /// The smallest hole the grid of a part `size` across reliably sees through, four cells across: 2 mm for most parts.
    public static func smallestSeenHole(forSize size: Vector3) -> Double {
        4 * cellSize(forSize: size)
    }

    /// The edge of a cell for a part `size` across: 0.5 mm or 1/32 of the longest side, whichever is finer, made coarser only as far as
    /// keeps the grid within `largestCellCount` cells. So a part of up to about 150 mm in each direction gets 0.5 mm cells, and a larger
    /// one gets cells in which a 2 mm hole is no longer seen (the check and Drain Holes say so).
    public static func cellSize(forSize size: Vector3) -> Double {
        let longest = max(size.x, size.y, size.z, 1e-6)
        var cell = min(largestCell, longest / 32)
        func cells(_ edge: Double) -> Double {
            [size.x, size.y, size.z].reduce(1) { $0 * ((max($1, 0) / edge).rounded(.up) + 4) }
        }
        while cells(cell) > Double(largestCellCount) { cell *= 1.02 }
        return cell
    }

    /// Cells along a side of the blocks `fill` classifies together.
    static let blockSide = 8
    /// The most cell centres asked for at once.
    static let batch = 1 << 18

    public let origin: Vector3
    public let cell: Double
    public let counts: SIMD3<Int>
    public private(set) var isSolid: [Bool]

    /// The cells for a part inside `bounds`, all empty.
    public init(bounds: BoundingBox) {
        let size = bounds.size
        cell = Self.cellSize(forSize: size)
        origin = bounds.min - Vector3(2 * cell, 2 * cell, 2 * cell)
        counts = SIMD3(Int((size.x / cell).rounded(.up)) + 4, Int((size.y / cell).rounded(.up)) + 4, Int((size.z / cell).rounded(.up)) + 4)
        isSolid = [Bool](repeating: false, count: counts.x * counts.y * counts.z)
    }

    public var cellCount: Int { isSolid.count }

    /// The flat number of cell (i, j, k), x fastest.
    public func index(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * counts.y + j) * counts.x + i }

    /// The cell numbers (i, j, k) of a flat index.
    public func coordinates(of index: Int) -> SIMD3<Int> {
        SIMD3(index % counts.x, (index / counts.x) % counts.y, index / (counts.x * counts.y))
    }

    /// The centre of the cell with this flat index.
    public func center(of index: Int) -> Vector3 {
        let c = coordinates(of: index)
        return origin + Vector3(Double(c.x) + 0.5, Double(c.y) + 0.5, Double(c.z) + 0.5) * cell
    }

    /// The flat index of the cell that holds `point`, or `nil` outside the grid.
    public func index(containing point: Vector3) -> Int? {
        let offset = (point - origin) * (1 / cell)
        guard offset.x.isFinite, offset.y.isFinite, offset.z.isFinite, offset.x >= 0, offset.y >= 0, offset.z >= 0 else { return nil }
        let (i, j, k) = (Int(offset.x), Int(offset.y), Int(offset.z))
        guard i < counts.x, j < counts.y, k < counts.z else { return nil }
        return index(i, j, k)
    }

    /// Sets whether the cell with this flat index is solid.
    public mutating func setSolid(_ solid: Bool, at index: Int) {
        isSolid[index] = solid
    }

    // MARK: Filling from a distance

    /// A run of cells, `low` to `high` (exclusive), classified together.
    struct Block {
        var low: SIMD3<Int>
        var high: SIMD3<Int>
    }

    /// What a block's centre value says about its cells: all solid, all empty, or each cell must be asked.
    enum Verdict {
        case solid, empty, undecided
    }

    /// The distance at which a cell is solid: half a cell.
    var reach: Double { cell / 2 * 1.0001 }

    func blocks() -> [Block] {
        var found: [Block] = []
        let side = Self.blockSide
        for k in stride(from: 0, to: counts.z, by: side) {
            for j in stride(from: 0, to: counts.y, by: side) {
                for i in stride(from: 0, to: counts.x, by: side) {
                    found.append(Block(low: SIMD3(i, j, k), high: SIMD3(min(i + side, counts.x), min(j + side, counts.y),
                                                                          min(k + side, counts.z))))
                }
            }
        }
        return found
    }

    /// The point in the middle of a block, and the distance from it to the farthest cell centre in it.
    func middle(of block: Block) -> (point: Vector3, radius: Double) {
        let low = origin + Vector3(Double(block.low.x), Double(block.low.y), Double(block.low.z)) * cell
        let high = origin + Vector3(Double(block.high.x), Double(block.high.y), Double(block.high.z)) * cell
        return ((low + high) * 0.5, (high - low).length / 2)
    }

    /// The signed distance is `lipschitz`-Lipschitz, so from `value` at a block's middle every cell centre in it is within `lipschitz × radius` of it.
    func verdict(value: Double, radius: Double, lipschitz: Double) -> Verdict {
        if value + lipschitz * radius <= reach { return .solid }
        if value - lipschitz * radius > reach { return .empty }
        return .undecided
    }

    mutating func mark(_ block: Block) {
        for k in block.low.z..<block.high.z {
            for j in block.low.y..<block.high.y {
                for i in block.low.x..<block.high.x { isSolid[index(i, j, k)] = true }
            }
        }
    }

    /// The flat indices and centres of the cells of `blocks`, in order.
    func cells(of blocks: ArraySlice<Block>) -> (indices: [Int], points: [Vector3]) {
        var indices: [Int] = []
        for block in blocks {
            for k in block.low.z..<block.high.z {
                for j in block.low.y..<block.high.y {
                    for i in block.low.x..<block.high.x { indices.append(index(i, j, k)) }
                }
            }
        }
        return (indices, indices.map { center(of: $0) })
    }

    /// The runs of undecided blocks that hold about `batch` cells each.
    func batches(of blocks: [Block]) -> [ArraySlice<Block>] {
        let perBatch = max(1, Self.batch / (Self.blockSide * Self.blockSide * Self.blockSide))
        return stride(from: 0, to: blocks.count, by: perBatch).map { blocks[$0..<min($0 + perBatch, blocks.count)] }
    }

    /// Fills the grid from a signed distance (negative inside, `lipschitz`-Lipschitz): a cell is solid when its centre is within half a
    /// cell of the surface or inside it. Blocks of 8 × 8 × 8 cells are first classified by the distance at their middle, and only the
    /// blocks the surface may cross are asked cell by cell, so the work follows the surface and not the volume. `distances` gives the
    /// distance at each of the points it is asked for, in order.
    public mutating func fill(lipschitz: Double = 1, from distances: ([Vector3]) throws -> [Double]) throws {
        let all = blocks()
        let middles = all.map { middle(of: $0) }
        var values: [Double] = []
        for start in stride(from: 0, to: middles.count, by: Self.batch) {
            try Task.checkCancellation()
            values += try distances(middles[start..<min(start + Self.batch, middles.count)].map(\.point))
        }
        var undecided: [Block] = []
        for (index, block) in all.enumerated() {
            switch verdict(value: values[index], radius: middles[index].radius, lipschitz: max(lipschitz, 1)) {
            case .solid: mark(block)
            case .empty: break
            case .undecided: undecided.append(block)
            }
        }
        for batch in batches(of: undecided) {
            try Task.checkCancellation()
            let (indices, points) = cells(of: batch)
            let found = try distances(points)
            for (offset, index) in indices.enumerated() { isSolid[index] = found[offset] <= reach }
        }
    }

    /// `fill(lipschitz:from:)` for a distance that has to be waited for (the GPU).
    public mutating func fill(lipschitz: Double = 1, awaiting distances: ([Vector3]) async throws -> [Double]) async throws {
        let all = blocks()
        let middles = all.map { middle(of: $0) }
        var values: [Double] = []
        for start in stride(from: 0, to: middles.count, by: Self.batch) {
            try Task.checkCancellation()
            values += try await distances(middles[start..<min(start + Self.batch, middles.count)].map(\.point))
        }
        var undecided: [Block] = []
        for (index, block) in all.enumerated() {
            switch verdict(value: values[index], radius: middles[index].radius, lipschitz: max(lipschitz, 1)) {
            case .solid: mark(block)
            case .empty: break
            case .undecided: undecided.append(block)
            }
        }
        for batch in batches(of: undecided) {
            try Task.checkCancellation()
            let (indices, points) = cells(of: batch)
            let found = try await distances(points)
            for (offset, index) in indices.enumerated() { isSolid[index] = found[offset] <= reach }
        }
    }
}
