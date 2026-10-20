import CreatorGeometry

/// The empty cells of an `OccupancyGrid` that the outside cannot reach (implicit spec §4.6): flood fill from the corner through
/// empty cells that share a face; whatever empty is left over is a pocket, and the pockets of more than one cell are voids.
///
/// A grid made from a mesh's unsigned distance (Errata D18) marks only the cells near the surface, so a pocket may be the inside of the
/// material as well as a cavity. Such a region is all on one side of the surface (a path out of it would cross the surface within half
/// a cell of a cell on the path), so `isInside` is asked about a few of its cell centres, and the region is a void only when most of them
/// are outside. The region's cells are never told apart one by one, which is what the pseudonormal sign did, and misread in a wedge
/// narrower than the cells. The inside of a thick part is one region of tens of millions of cells, so a region is judged once `judgedAt`
/// of its cells are listed, and one judged to be material is not listed any further.
public struct EnclosedVoids: Sendable {
    /// How many cell centres of a region `isInside` is asked about.
    static let samples = 5

    /// How many cells of a region are listed before it is judged: a region that goes on is judged by these, and dropped from the list
    /// when it is material. Smaller regions are judged when the fill ends.
    static let judgedAt = 4096

    /// The void each cell belongs to, or -1.
    public let label: [Int32]
    /// The flat cell indices of each void, in order of their lowest flat index.
    public let voids: [[Int32]]

    /// - Parameter isInside: whether a point is inside the part, for a grid that holds only the cells near the surface. `nil` for a grid
    ///   that already counts the inside as solid (an implicit solid's, whose inside test is the sign of its own field).
    public init(_ grid: OccupancyGrid, isInside: ((Vector3) -> Bool)? = nil) throws {
        let counts = grid.counts
        let strides = [1, counts.x, counts.x * counts.y]
        var reached = grid.isSolid
        /// Marks everything reachable from `start`. The cells are listed in `collecting` when it is given; the outside pass gives none,
        /// so the biggest region of the grid is never stored. With `judging`, the region is judged when `judgedAt` cells are listed: when
        /// it is material the list is dropped (`collecting` becomes `nil`) and the fill goes on without it. Returns that verdict, or
        /// `nil` when the region ended first or there was no judge.
        @discardableResult
        func fill(from start: Int, collecting: inout [Int32]?, judging: (([Int32]) -> Bool)? = nil) throws -> Bool? {
            var stack = [Int32(start)]
            var visited = 0
            var verdict: Bool?
            reached[start] = true
            while let next = stack.popLast() {
                if visited & 0xFFFF == 0 { try Task.checkCancellation() }
                visited += 1
                collecting?.append(next)
                if verdict == nil, collecting?.count == Self.judgedAt, let judging, let listed = collecting {
                    verdict = judging(listed)
                    if verdict == true { collecting = nil }
                }
                let c = grid.coordinates(of: Int(next))
                for axis in 0..<3 {
                    for step in [-1, 1] where c[axis] + step >= 0 && c[axis] + step < counts[axis] {
                        let neighbour = Int(next) + step * strides[axis]
                        if !reached[neighbour] {
                            reached[neighbour] = true
                            stack.append(Int32(neighbour))
                        }
                    }
                }
            }
            return verdict
        }
        let judge = isInside.map { isInside in { (cells: [Int32]) in Self.isMaterial(cells, in: grid, isInside) } }
        // The corner is padding, so empty: everything the fill reaches is outside.
        var nothing: [Int32]?
        if !reached[0] { try fill(from: 0, collecting: &nothing) }
        var label = [Int32](repeating: -1, count: grid.cellCount)
        var voids: [[Int32]] = []
        for start in 0..<grid.cellCount where !reached[start] {
            var listed: [Int32]? = []
            let early = try fill(from: start, collecting: &listed, judging: judge)
            let cells = listed ?? []
            // A pocket of a single cell is below what the grid can tell from the surface; one judged material is not a void.
            guard cells.count > 1, early != true else { continue }
            if early == nil, let judge, judge(cells) { continue }
            for cell in cells { label[Int(cell)] = Int32(voids.count) }
            voids.append(cells)
        }
        self.label = label
        self.voids = voids
    }

    /// Whether most of `Self.samples` cell centres, spread through `cells`, are inside the part.
    private static func isMaterial(_ cells: [Int32], in grid: OccupancyGrid, _ isInside: (Vector3) -> Bool) -> Bool {
        let picks = Set((0..<samples).map { cells[$0 * (cells.count - 1) / (samples - 1)] })
        let inside = picks.filter { isInside(grid.center(of: Int($0))) }.count
        return 2 * inside > picks.count
    }
}
