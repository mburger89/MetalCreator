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

    static func struts(_ cell: StrutCell, cells: LatticeCells, radius: Grading, blend: Double = 0) -> ImplicitSolid {
        .struts(StrutLattice(cell: cell, cells: cells, radius: radius, blend: blend, region: region))
    }

    static let strutsAll: [(name: String, solid: ImplicitSolid)] = [
        ("cubic struts", struts(.cubic, cells: cells(6), radius: .constant(0.6))),
        ("bcc struts, graded cell, blended", struts(.bcc, cells: gradedCell, radius: .constant(0.5), blend: 0.3)),
        ("fcc struts", struts(.fcc, cells: cells(7), radius: .constant(0.5))),
        ("octet struts, graded radius", struts(.octet, cells: cells(8), radius: ImplicitFixtures.graded)),
        ("kelvin struts, stretched", struts(.kelvin, cells: cells(8, stretch: Vector3(2, 1, 1)), radius: .constant(0.5))),
        ("diamond struts, noisy radius", struts(.diamond, cells: cells(9), radius: ImplicitFixtures.noisy)),
    ]

    /// `count` seeds spread through `box` by a seeded generator.
    static func seeds(_ count: Int, in box: BoundingBox = region, seed: Int) -> [Vector3] {
        let random = SeededRandom(seed: seed, stream: 3)
        return (0..<count).map { index in
            Vector3(box.min.x + box.size.x * random.unit(at: 3 * index), box.min.y + box.size.y * random.unit(at: 3 * index + 1),
                    box.min.z + box.size.z * random.unit(at: 3 * index + 2))
        }
    }

    static func voronoi(_ points: [Vector3], _ form: VoronoiForm, thickness: Grading, radius: Double? = nil,
                        in box: BoundingBox = region) -> ImplicitSolid {
        let seeds = VoronoiSeeds(points: points, radius: radius ?? VoronoiSeeds.searchRadius(count: points.count, in: box))
        return .voronoi(VoronoiLattice(seeds: seeds, form: form, thickness: thickness, region: box))
    }

    static let voronoiAll: [(name: String, solid: ImplicitSolid)] = [
        ("voronoi struts", voronoi(seeds(36, seed: 1), .struts, thickness: .constant(1))),
        ("voronoi foam, graded wall", voronoi(seeds(36, seed: 2), .foam, thickness: ImplicitFixtures.graded)),
    ]

    static var all: [(name: String, solid: ImplicitSolid)] { tpmsAll + strutsAll + voronoiAll }

    // MARK: Mappings (implicit spec §3.5)

    /// The axis (or the polar axis, or the centre) that crosses `region`, so the singular set is in play, and the half-plane of the cut
    /// crosses it too.
    static let crossing = Vector3(8, 4, 0)
    /// An axis 30 mm to the side of `region`: no singular set, no cut inside the region.
    static let beside = Vector3(-30, 4, 0)

    /// The radius a mapping about `point` is wound on, as the node's mean radius is: 9 mm where the region holds the point, else the
    /// distance to the region's middle (a radius far from the real one would squeeze the cells along the angle and make the field's
    /// slope there small, which the GPU-against-CPU mesh comparison is rightly strict about).
    static func radius(about point: Vector3, flat: Bool) -> Double {
        let offset = region.center - point
        return max(9, (flat ? Vector3(offset.x, offset.y, 0) : offset).length)
    }

    /// - Parameter radius: the radius the angle is wound on, when it is not the region's mean about `point`.
    static func cylinder(through point: Vector3, cell: Double?, radius: Double? = nil) -> LatticeMapping {
        let mean = LatticeMapping.turnRadius(mean: radius ?? Self.radius(about: point, flat: true), cell: cell)
        return CylindricalMap(axis: Plane(origin: point, normal: .unitZ, xAxis: .unitX), radius: mean, over: region)
            .map(LatticeMapping.cylindrical) ?? .straight
    }

    static func sphere(at centre: Vector3, cell: Double?) -> LatticeMapping {
        SphericalMap(centre: centre, radius: LatticeMapping.turnRadius(mean: radius(about: centre, flat: false), cell: cell), over: region)
            .map(LatticeMapping.spherical) ?? .straight
    }

    /// `solid` with its mapping replaced.
    static func mapped(_ solid: ImplicitSolid, _ mapping: LatticeMapping) -> ImplicitSolid {
        switch solid {
        case .tpms(var lattice):
            lattice.mapping = mapping
            return .tpms(lattice)
        case .struts(var lattice):
            lattice.mapping = mapping
            return .struts(lattice)
        case .voronoi(var lattice):
            lattice.mapping = mapping
            return .voronoi(lattice)
        default:
            return solid
        }
    }

    static func mappedVoronoi(_ count: Int, _ form: VoronoiForm, seed: Int, mapping: LatticeMapping) -> ImplicitSolid {
        let seeds = VoronoiSeeds.mapped(points: seeds(count, seed: seed), mapping: mapping, region: region)
        return .voronoi(VoronoiLattice(seeds: seeds, form: form, thickness: .constant(1), region: region, mapping: mapping))
    }

    /// Every node under the mappings that are not Straight. Where the cell is constant the turn is whole cells, so the pattern meets
    /// itself at the cut that crosses the region; the graded ones keep the cut outside it.
    static var mappedAll: [(name: String, solid: ImplicitSolid)] {
        [
            ("gyroid, cylindrical through the region", mapped(tpmsAll[0].solid, cylinder(through: crossing, cell: 8))),
            ("schwarz P, cylindrical beside the region, graded cell", mapped(tpmsAll[1].solid, cylinder(through: beside, cell: nil))),
            ("diamond, graded cell, spherical beside the region", mapped(tpmsAll[2].solid, sphere(at: beside, cell: nil))),
            ("neovius, spherical about a point of the region", mapped(tpmsAll[3].solid, sphere(at: crossing, cell: 9))),
            ("cubic struts, spherical about a point of the region", mapped(strutsAll[0].solid, sphere(at: crossing, cell: 6))),
            ("fcc struts, cylindrical through the region", mapped(strutsAll[2].solid, cylinder(through: crossing, cell: 7))),
            ("bcc struts, graded cell, blended, cylindrical beside", mapped(strutsAll[1].solid, cylinder(through: beside, cell: nil))),
            ("voronoi struts, cylindrical through the region",
             mappedVoronoi(36, .struts, seed: 1, mapping: cylinder(through: crossing, cell: nil))),
            ("voronoi foam, spherical beside the region", mappedVoronoi(36, .foam, seed: 2, mapping: sphere(at: beside, cell: nil))),
        ]
    }

    // MARK: Face mapping (implicit spec §3.5)

    /// The side of a cylinder of 14 mm about the Z axis through the point the other mappings cross, charted over the region and its
    /// margin: made once, because measuring it takes a second or two.
    static let cylinderChart = SyntheticFace.cylinder(
        radius: 14, axis: Vector2(crossing.x, crossing.y), covering: ImplicitSolid.grown(region, by: 8), spacing: 0.7)

    static func face(cell: Double?) -> LatticeMapping {
        .face(FaceMap(chart: cylinderChart, firstCell: cell, secondCell: cell))
    }

    /// Every node under the Face mapping on a cylinder's side that the region's axis crosses, so the seam, the singular cells and the
    /// cells that follow the skin are all in play.
    static var faceAll: [(name: String, solid: ImplicitSolid)] {
        [
            ("gyroid, face of a cylinder", mapped(tpmsAll[0].solid, face(cell: 8))),
            ("cubic struts, face of a cylinder", mapped(strutsAll[0].solid, face(cell: 6))),
            ("voronoi struts, face of a cylinder", mappedVoronoi(36, .struts, seed: 3, mapping: face(cell: nil))),
        ]
    }

    /// The same cylinder charted with its axis 28 mm to the side of the region, so the region is outside it (fins on a pipe): the face's
    /// depth is positive throughout, there is no centre of curvature in the region, and the chart has no singular cell.
    static let outsideChart = SyntheticFace.cylinder(
        radius: 14, axis: Vector2(-20, crossing.y), covering: ImplicitSolid.grown(region, by: 8), spacing: 0.7)

    /// The Face mapping with no singular cell in the region: what the GPU mesh comparison runs on. (Within a few millimetres of a
    /// singular set the map stretches the GPU's float rounding, 2e-5 mm in value, into slides of up to 2e-3 mm along near-tangent mesh
    /// edges, past D17's allowance; the values still agree to 1e-4 there, which `GPUAgreementTests` checks on `faceAll`.)
    static var faceOutsideAll: [(name: String, solid: ImplicitSolid)] {
        let cells = LatticeMapping.face(FaceMap(chart: outsideChart, firstCell: 8, secondCell: 8))
        let seeds = LatticeMapping.face(FaceMap(chart: outsideChart, firstCell: nil, secondCell: nil))
        return [
            ("gyroid, face outside a cylinder", mapped(tpmsAll[0].solid, cells)),
            ("voronoi foam, face outside a cylinder", mappedVoronoi(36, .foam, seed: 4, mapping: seeds)),
        ]
    }

    /// The mapped fixtures and the face-mapped ones.
    static var everyMapped: [(name: String, solid: ImplicitSolid)] { mappedAll + faceAll + faceOutsideAll }
}
