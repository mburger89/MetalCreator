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
}
