import Foundation

/// What a face chart's samples say about the map they interpolate (implicit spec §3.5): which cells stretch it too far, how fast it
/// changes everywhere else, and how far each sample is from the cells that do.
///
/// The map's value in a cell is the trilinear interpolation of the samples, so the largest change per millimetre in the cell is the
/// largest sample difference at its corners: the squared gradient of a trilinear function is convex along every axis, so it peaks at a
/// corner. A periodic coordinate is interpolated as a cosine and sine and turned into an angle after, which shortens the vector in
/// the cell by at most the cosine of half the angle between its corners, so its slope is divided by that.
struct FaceChartAnalysis {
    /// A coordinate's samples: the values, or the cosine and sine of an angle with the length of a radian in millimetres.
    enum Samples {
        case linear([Float])
        case angle(cosine: [Float], sine: [Float], radius: Double)

        var isAngle: Bool { if case .angle = self { true } else { false } }

        /// The length of a radian in millimetres for an angle, else 1: what turns the coordinate's slope into millimetres per millimetre.
        var radius: Double { if case .angle(_, _, let radius) = self { radius } else { 1 } }
    }

    /// A cell of the grid by its lowest sample, and one of its eight corners (bit 0 is x, bit 1 is y, bit 2 is z).
    private struct Cell {
        var i: Int
        var j: Int
        var k: Int
    }

    /// For each sample, true when it is a corner of a singular cell.
    var singularVertices: [Bool]
    var slopes: (first: Double, second: Double, depth: Double)

    /// Cells with an angle spread this wide (twice the largest angle from the first corner) are singular: the interpolated vector can
    /// shrink to nothing.
    static let widestSpread = 2.0

    /// - Parameters:
    ///   - limit: a cell whose map stretches by more than this, in millimetres per millimetre, is singular.
    static func run(grid: FaceChartGrid, first: Samples, second: Samples, depth: [Float], limit: Double) -> FaceChartAnalysis {
        let reader = Reader(grid: grid, first: first, second: second, depth: .linear(depth))
        var singular = [Bool](repeating: false, count: grid.sampleCount)
        var slopes = (first: 0.0, second: 0.0, depth: 0.0)
        for k in 0..<reader.counts[2] - 1 {
            for j in 0..<reader.counts[1] - 1 {
                for i in 0..<reader.counts[0] - 1 {
                    let cell = Cell(i: i, j: j, k: k)
                    guard let measured = reader.measure(cell), measured.stretch <= limit else {
                        for corner in 0..<8 { singular[reader.index(cell, corner)] = true }
                        continue
                    }
                    slopes = (max(slopes.first, measured.first), max(slopes.second, measured.second), max(slopes.depth, measured.depth))
                }
            }
        }
        return FaceChartAnalysis(singularVertices: singular, slopes: slopes)
    }

    /// What one cell does to the map: how far it stretches and how fast each coordinate changes at its worst corner.
    private struct Measure {
        var stretch = 0.0
        var first = 0.0
        var second = 0.0
        var depth = 0.0
    }

    /// Reads the samples of a grid by cell and corner.
    private struct Reader {
        let counts: [Int]
        let step: Float
        let first: Samples
        let second: Samples
        let depth: Samples

        init(grid: FaceChartGrid, first: Samples, second: Samples, depth: Samples) {
            counts = grid.counts
            step = Float(grid.spacing)
            self.first = first
            self.second = second
            self.depth = depth
        }

        func index(_ cell: Cell, _ corner: Int) -> Int {
            ((cell.k + (corner >> 2)) * counts[1] + cell.j + ((corner >> 1) & 1)) * counts[0] + cell.i + (corner & 1)
        }

        private func index(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * counts[1] + j) * counts[0] + i }

        /// The gradient of plain samples at a corner: the sample differences along the three edges of the cell that meet there.
        private func gradient(_ values: [Float], _ cell: Cell, _ corner: Int) -> (Float, Float, Float) {
            let (a, b, c) = (corner & 1, (corner >> 1) & 1, corner >> 2)
            let (i, j, k) = (cell.i, cell.j, cell.k)
            return ((values[index(i + 1, j + b, k + c)] - values[index(i, j + b, k + c)]) / step,
                    (values[index(i + a, j + 1, k + c)] - values[index(i + a, j, k + c)]) / step,
                    (values[index(i + a, j + b, k + 1)] - values[index(i + a, j + b, k)]) / step)
        }

        /// The size of the gradient of a coordinate at a corner: millimetres per millimetre, or radians per millimetre for an angle.
        private func size(_ samples: Samples, _ cell: Cell, _ corner: Int) -> Float {
            switch samples {
            case .linear(let values):
                let g = gradient(values, cell, corner)
                return (g.0 * g.0 + g.1 * g.1 + g.2 * g.2).squareRoot()
            case .angle(let cosine, let sine, _):
                let (gc, gs) = (gradient(cosine, cell, corner), gradient(sine, cell, corner))
                let at = index(cell, corner)
                let (c0, s0) = (cosine[at], sine[at])
                let across = (c0 * gs.0 - s0 * gc.0, c0 * gs.1 - s0 * gc.1, c0 * gs.2 - s0 * gc.2)
                return (across.0 * across.0 + across.1 * across.1 + across.2 * across.2).squareRoot() / max(c0 * c0 + s0 * s0, 1e-6)
            }
        }

        /// The largest angle in the cell from its first corner's, in radians; infinite if a sample is not a number.
        private func spread(_ samples: Samples, _ cell: Cell) -> Float {
            guard case .angle(let cosine, let sine, _) = samples else { return 0 }
            let reference = atan2(sine[index(cell, 0)], cosine[index(cell, 0)])
            var widest: Float = 0
            for corner in 1..<8 {
                let at = index(cell, corner)
                var gap = abs(atan2(sine[at], cosine[at]) - reference)
                if gap > Float.pi { gap = 2 * Float.pi - gap }
                widest = max(widest, gap)
            }
            return widest.isNaN ? .infinity : widest
        }

        private func isFinite(_ samples: Samples, _ at: Int) -> Bool {
            switch samples {
            case .linear(let values): values[at].isFinite
            case .angle(let cosine, let sine, _): cosine[at].isFinite && sine[at].isFinite
            }
        }

        /// The cell's stretch and slopes, or `nil` when it has a sample that is not a number or an angle spread too wide to interpolate.
        func measure(_ cell: Cell) -> Measure? {
            for corner in 0..<8 {
                let at = index(cell, corner)
                guard isFinite(first, at), isFinite(second, at), isFinite(depth, at) else { return nil }
            }
            let widest = max(spread(first, cell), spread(second, cell))
            guard widest * 2 < Float(FaceChartAnalysis.widestSpread) else { return nil }
            let factor = 1 / Double(cos(widest))
            var measure = Measure()
            for corner in 0..<8 {
                let slopes = (first: Double(size(first, cell, corner)) * (first.isAngle ? factor : 1),
                              second: Double(size(second, cell, corner)) * (second.isAngle ? factor : 1),
                              depth: Double(size(depth, cell, corner)))
                let scaled = (slopes.first * first.radius, slopes.second * second.radius, slopes.depth)
                measure.stretch = max(measure.stretch, (scaled.0 * scaled.0 + scaled.1 * scaled.1 + scaled.2 * scaled.2).squareRoot())
                measure.first = max(measure.first, slopes.first)
                measure.second = max(measure.second, slopes.second)
                measure.depth = max(measure.depth, slopes.depth)
            }
            return measure
        }
    }

    /// The distance from each sample to the nearest singular one, in millimetres and held to `cap`: two chamfer sweeps with the true
    /// lengths of the 26 neighbours' steps, which is within 5% of the Euclidean distance and never below it.
    static func distances(from singular: [Bool], grid: FaceChartGrid, cap: Double) -> [Float] {
        let counts = grid.counts
        let limit = Float(cap)
        var field = singular.map { $0 ? Float(0) : limit }
        var offsets: [(Int, Int, Int, Float)] = []
        for dk in -1...1 {
            for dj in -1...1 {
                for di in -1...1 where (dk, dj, di) != (0, 0, 0) {
                    offsets.append((di, dj, dk, Float(grid.spacing) * Float(abs(dk) + abs(dj) + abs(di)).squareRoot()))
                }
            }
        }
        // The neighbours already swept going forward are the ones before a sample in numbering order, and going back the ones after.
        sweep(&field, counts, forward: true, neighbours: offsets.filter { ($0.2, $0.1, $0.0) < (0, 0, 0) })
        sweep(&field, counts, forward: false, neighbours: offsets.filter { ($0.2, $0.1, $0.0) > (0, 0, 0) })
        return field.map { min($0, limit) }
    }

    private static func sweep(_ field: inout [Float], _ counts: [Int], forward: Bool, neighbours: [(Int, Int, Int, Float)]) {
        let (nx, ny, nz) = (counts[0], counts[1], counts[2])
        let order = { (count: Int) in forward ? Array(0..<count) : Array((0..<count).reversed()) }
        for k in order(nz) {
            for j in order(ny) {
                for i in order(nx) {
                    let here = (k * ny + j) * nx + i
                    var best = field[here]
                    for (di, dj, dk, step) in neighbours {
                        let (a, b, c) = (i + di, j + dj, k + dk)
                        guard a >= 0, a < nx, b >= 0, b < ny, c >= 0, c < nz else { continue }
                        best = min(best, field[(c * ny + b) * nx + a] + step)
                    }
                    field[here] = best
                }
            }
        }
    }
}
