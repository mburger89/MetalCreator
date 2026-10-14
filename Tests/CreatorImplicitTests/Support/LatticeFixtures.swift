import CreatorGeometry
import CreatorGraph
import CreatorImplicit

/// One lattice of every kind and variation, for the tests that run over all solids (`ImplicitFixtures.all`, `GPUFixtures.all`).
enum LatticeFixtures {
    /// A region away from the origin, so the pattern is not centred on it.
    static let region = BoundingBox(min: Vector3(-6, -10, -14), max: Vector3(22, 18, 14))

    /// 6 + z / 10: between 4.6 and 7.4 mm over the region, slope 0.1 per mm.
    static var gradedCell: LatticeCells {
        let field = Field.add(.constant(6), .linearGradient(plane: .xy, length: 10))
        return LatticeCells(size: Grading(field: field, range: 4.6...7.4, slope: field.slopeBound.value))
    }

    static func cells(_ size: Double, stretch: Vector3 = Vector3(1, 1, 1)) -> LatticeCells {
        LatticeCells(size: .constant(size), stretch: stretch)
    }

    static func tpms(_ type: TPMSType, _ form: TPMSForm, cells: LatticeCells, thickness: Grading) -> ImplicitSolid {
        .tpms(TPMSLattice(type: type, form: form, cells: cells, thickness: thickness, region: region))
    }

    static let tpmsAll: [(name: String, solid: ImplicitSolid)] = [
        ("gyroid sheet", tpms(.gyroid, .sheet, cells: cells(8), thickness: .constant(1.2))),
        ("schwarz P network", tpms(.schwarzP, .network, cells: cells(7), thickness: .constant(0.8))),
        ("diamond sheet, graded cell", tpms(.diamond, .sheet, cells: gradedCell, thickness: .constant(0.9))),
        ("neovius sheet, stretched, noisy wall", tpms(.neovius, .sheet, cells: cells(9, stretch: Vector3(1, 1, 2)),
                                                       thickness: ImplicitFixtures.noisy)),
        ("lidinoid network, graded wall", tpms(.lidinoid, .network, cells: cells(8), thickness: ImplicitFixtures.graded)),
    ]

    static var all: [(name: String, solid: ImplicitSolid)] { tpmsAll }
}
