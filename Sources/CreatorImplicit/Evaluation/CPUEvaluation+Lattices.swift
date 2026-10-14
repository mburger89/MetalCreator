import CreatorGeometry
import Foundation

/// The lattice cases of the reference evaluation (implicit spec §3.4). Each is a line-for-line twin of its function in
/// `ImplicitShaderLibrary+Lattices`.
extension CPUEvaluation {
    /// The cell size at `p` and the size of a cell along each axis.
    func cellScale(_ cells: LatticeCells, at p: Vector3) -> (size: Double, edges: Vector3) {
        let size = max(value(cells.size, at: p), LatticeCells.minimumSize)
        return (size, Vector3(size * cells.stretch.x, size * cells.stretch.y, size * cells.stretch.z))
    }

    func tpms(_ lattice: TPMSLattice, at p: Vector3) -> Double {
        let (size, edges) = cellScale(lattice.cells, at: p)
        let q = Vector3(p.x / edges.x, p.y / edges.y, p.z / edges.z) * (2 * Double.pi)
        let core = lattice.type.value(at: q) * size / (2 * Double.pi * lattice.type.wallScale)
        let wall = max(0, value(lattice.thickness, at: p))
        let body = switch lattice.form {
        case .sheet: abs(core) - wall / 2
        case .network: core - wall / 2
        }
        return max(body, Self.boxDistance(p, lattice.region))
    }

    func struts(_ lattice: StrutLattice, at p: Vector3) -> Double {
        let (_, edges) = cellScale(lattice.cells, at: p)
        let index = Vector3(floor(p.x / edges.x), floor(p.y / edges.y), floor(p.z / edges.z))
        let radius = max(0, value(lattice.radius, at: p))
        let blend = lattice.blend
        var nearest = 1e30
        for dz in -1...1 {
            for dy in -1...1 {
                for dx in -1...1 {
                    let base = index + Vector3(Double(dx), Double(dy), Double(dz))
                    for strut in lattice.cell.struts {
                        let start = Vector3((base.x + strut.start.x) * edges.x, (base.y + strut.start.y) * edges.y,
                                            (base.z + strut.start.z) * edges.z)
                        let end = Vector3((base.x + strut.end.x) * edges.x, (base.y + strut.end.y) * edges.y,
                                          (base.z + strut.end.z) * edges.z)
                        let gap = Self.segmentDistance(p, start, end)
                        nearest = blend > 0 ? Self.smoothMinimum(nearest, gap, width: blend) : min(nearest, gap)
                    }
                }
            }
        }
        let reach = StrutLattice.reachInCells * min(edges.x, edges.y, edges.z)
        return max(min(nearest, reach) - radius, Self.boxDistance(p, lattice.region))
    }

    /// The distance from `p` to the segment from `a` to `b`.
    static func segmentDistance(_ p: Vector3, _ a: Vector3, _ b: Vector3) -> Double {
        let along = b - a
        let length2 = along.dot(along)
        let t = length2 > 0 ? min(max((p - a).dot(along) / length2, 0), 1) : 0
        return (p - a - along * t).length
    }

    // MARK: Voronoi

    func voronoi(_ lattice: VoronoiLattice, at p: Vector3) -> Double {
        let seeds = lattice.seeds
        let radius = seeds.radius
        var (d1, d2, d3) = (Double.infinity, Double.infinity, Double.infinity)
        var nearest = -1
        seeds.forEachSeed(near: p) { seed, position in
            let d = (p - position).length
            if d < d1 {
                (d3, d2, d1, nearest) = (d2, d1, d, seed)
            } else if d < d2 {
                (d3, d2) = (d2, d)
            } else if d < d3 {
                d3 = d
            }
        }
        let wall = max(0, value(lattice.thickness, at: p))
        let body: Double
        switch lattice.form {
        case .struts:
            body = (min(d3, radius) - min(d1, radius)) / VoronoiLattice.strutScale - wall / 2
        case .foam:
            var distance = max(0, (radius - d1) / 2)
            if nearest >= 0 {
                let first = seeds.points[nearest]
                seeds.forEachSeed(near: p) { seed, position in
                    let across = position - first
                    let length = across.length
                    guard seed != nearest, length > 1e-9 else { return }
                    distance = min(distance, across.dot((first + position) * 0.5 - p) / length)
                }
            }
            body = distance - wall / 2
        }
        return max(body, Self.boxDistance(p, lattice.region))
    }
}
