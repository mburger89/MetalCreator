/// The empty cells of an `OccupancyGrid` that the outside cannot reach (implicit spec §4.6): flood fill from the corner through
/// empty cells that share a face; whatever empty is left over is a pocket, and the pockets of more than one cell are voids.
public struct EnclosedVoids: Sendable {
    /// The void each cell belongs to, or -1.
    public let label: [Int32]
    /// The flat cell indices of each void, in order of their lowest flat index.
    public let voids: [[Int32]]

    public init(_ grid: OccupancyGrid) throws {
        let counts = grid.counts
        let strides = [1, counts.x, counts.x * counts.y]
        var reached = grid.isSolid
        func fill(from start: Int, collecting: inout [Int32]) throws {
            var stack = [Int32(start)]
            reached[start] = true
            while let next = stack.popLast() {
                if collecting.count & 0xFFFF == 0 { try Task.checkCancellation() }
                collecting.append(next)
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
        }
        // The corner is padding, so empty: everything the fill reaches is outside.
        var outside: [Int32] = []
        if !reached[0] { try fill(from: 0, collecting: &outside) }
        var label = [Int32](repeating: -1, count: grid.cellCount)
        var voids: [[Int32]] = []
        for start in 0..<grid.cellCount where !reached[start] {
            var cells: [Int32] = []
            try fill(from: start, collecting: &cells)
            // A pocket of a single cell is below what the grid can tell from the surface.
            guard cells.count > 1 else { continue }
            for cell in cells { label[Int(cell)] = Int32(voids.count) }
            voids.append(cells)
        }
        self.label = label
        self.voids = voids
    }
}
