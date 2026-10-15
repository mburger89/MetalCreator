import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The TPMS lattice (implicit spec §3.4, §7): hand-worked values of each surface, the wall thickness the scale factor is pinned to,
/// the cell size field, the clip to the region and the constants the lipschitz bound is made from.
struct TPMSLatticeTests {
    static let region = BoundingBox(min: Vector3(-40, -40, -40), max: Vector3(40, 40, 40))
    static let twoPi = 2 * Double.pi

    func lattice(_ type: TPMSType = .gyroid, _ form: TPMSForm = .sheet, cell: Double = Self.twoPi, thickness: Double = 0.5,
                 stretch: Vector3 = Vector3(1, 1, 1)) -> ImplicitSolid {
        LatticeFixtures.tpms(type, form, cells: LatticeFixtures.cells(cell, stretch: stretch), thickness: .constant(thickness))
            .withRegion(Self.region)
    }

    func value(_ solid: ImplicitSolid, _ x: Double, _ y: Double, _ z: Double) -> Double {
        solid.signedDistance(at: Vector3(x, y, z))
    }

    // MARK: The surfaces

    /// g at hand-worked points (q in radians; a cell of 2π mm makes q the point itself).
    @Test(arguments: [
        (TPMSType.gyroid, Vector3(0, 0, 0), 0.0), (.gyroid, Vector3(Double.pi / 2, 0, 0), 1),
        (.schwarzP, Vector3(0, 0, 0), 3), (.schwarzP, Vector3(Double.pi, 0, 0), 1),
        (.diamond, Vector3(0, 0, 0), 0), (.diamond, Vector3(Double.pi / 2, Double.pi / 2, Double.pi / 2), 1),
        (.neovius, Vector3(0, 0, 0), 13), (.neovius, Vector3(Double.pi, Double.pi, Double.pi), -13),
        (.lidinoid, Vector3(0, 0, 0), -1.35), (.lidinoid, Vector3(Double.pi / 2, 0, 0), 0.65),
    ])
    func eachSurfaceHasItsKnownValues(_ type: TPMSType, _ q: Vector3, _ expected: Double) {
        #expect(abs(type.value(at: q) - expected) < 1e-12)
    }

    @Test func aSheetIsTheScaledSurfaceLessHalfTheWall() {
        let solid = lattice(.gyroid, .sheet, thickness: 0.5)
        let wall = TPMSType.gyroid.wallScale
        // Cell 2π: the lattice coordinates are the point, and g(π/2, 0, 0) = 1, so the core is 1 / wallScale.
        #expect(abs(value(solid, Double.pi / 2, 0, 0) - (1 / wall - 0.25)) < 1e-12)
        let below = TPMSType.gyroid.value(at: Vector3(-Double.pi / 2, 0, 0))
        #expect(abs(value(solid, -Double.pi / 2, 0, 0) - (abs(below) / wall - 0.25)) < 1e-12, "the sheet is symmetric about g = 0")
        #expect(abs(value(solid, 0, 0, 0) + 0.25) < 1e-12, "on the surface the value is minus half the wall")
    }

    @Test func aNetworkIsOneSideOfTheSurfaceGrownByHalfTheThickness() {
        let solid = lattice(.schwarzP, .network, thickness: 0.5)
        let wall = TPMSType.schwarzP.wallScale
        #expect(abs(value(solid, 0, 0, 0) - (3 / wall - 0.25)) < 1e-12)
        #expect(abs(value(solid, Double.pi, 0, 0) - (1 / wall - 0.25)) < 1e-12)
        let thin = lattice(.schwarzP, .network, thickness: 0)
        #expect(abs(value(thin, Double.pi / 2, Double.pi / 2, Double.pi / 2)) < 1e-12 && value(thin, 0, 0, 0) > 0)
    }

    @Test func theLatticeRepeatsWithTheCellAlongEachAxis() {
        let solid = lattice(.diamond, .sheet, cell: 5, thickness: 0.7)
        for (x, y, z) in [(0.3, 1.1, -2.7), (4.9, -3.3, 6.1), (-7.2, 0.4, 2.2)] {
            let here = value(solid, x, y, z)
            #expect(abs(value(solid, x + 5, y, z) - here) < 1e-9)
            #expect(abs(value(solid, x, y - 10, z) - here) < 1e-9)
            #expect(abs(value(solid, x, y, z + 15) - here) < 1e-9)
        }
    }

    @Test func aStretchMakesTheCellLongerOnThatAxisAndKeepsItsVolume() {
        let solid = lattice(.gyroid, .sheet, cell: 4, thickness: 0.5, stretch: Vector3(1, 1, 2))
        guard case .tpms(let made) = solid else { Issue.record("not a TPMS"); return }
        let mean = made.cells.stretch.x * made.cells.stretch.y * made.cells.stretch.z
        #expect(abs(mean - 1) < 1e-12 && abs(made.cells.stretch.z / made.cells.stretch.x - 2) < 1e-12)
        let period = 4 * made.cells.stretch.z
        let here = value(solid, 0.7, 1.9, -0.4)
        #expect(abs(value(solid, 0.7, 1.9, -0.4 + period) - here) < 1e-9)
        #expect(abs(value(solid, 0.7, 1.9, -0.4 + period / 2) - here) > 1e-3, "not half the period")
    }

    // MARK: Thickness

    /// The volume of the lattice in one cell as a fraction of the cell, on a grid of `steps`³ points at cell centres.
    func solidFraction(_ solid: ImplicitSolid, cell: Double, steps: Int) -> Double {
        let h = cell / Double(steps)
        var inside = 0
        var points: [Vector3] = []
        points.reserveCapacity(steps * steps * steps)
        for i in 0..<steps {
            for j in 0..<steps {
                for k in 0..<steps { points.append(Vector3((Double(i) + 0.5) * h, (Double(j) + 0.5) * h, (Double(k) + 0.5) * h)) }
            }
        }
        for v in solid.signedDistances(at: points) where v < 0 { inside += 1 }
        return Double(inside) / Double(points.count)
    }

    /// Errata of the spec §3.4: "the factor and its error are pinned in tests (a gyroid's wall within 5%)". A wall of thickness t on a
    /// surface of area A holds t × A of volume to first order, and the gyroid's area is 3.0915 a² per cell (Schoen), so a sheet of
    /// t = 0.05 a fills 15.5% of its cell.
    @Test func aGyroidSheetsMeanWallIsItsThicknessToWithinFivePercent() {
        let cell = 8.0
        for thickness in [0.2, 0.4] {
            let fraction = solidFraction(lattice(.gyroid, .sheet, cell: cell, thickness: thickness), cell: cell, steps: 64)
            let measured = fraction * cell * cell * cell / (3.0915 * cell * cell)
            #expect(abs(measured / thickness - 1) < 0.05, "t = \(thickness): the mean wall is \(measured) mm")
        }
    }

    @Test func aGyroidNetworkWithNoThicknessFillsHalfTheCell() {
        let fraction = solidFraction(lattice(.gyroid, .network, cell: 8, thickness: 0), cell: 8, steps: 48)
        #expect(abs(fraction - 0.5) < 0.01)
    }

    // MARK: The constants

    /// g and its gradient on a grid of one period, for the bounds and the wall scale below.
    func survey(_ type: TPMSType, steps: Int, shell: Double) -> (maxGradient: Double, maxValue: Double, shellGradient: Double) {
        let h = Self.twoPi / Double(steps), d = 1e-5
        var (maxGradient, maxValue, sum, count) = (0.0, 0.0, 0.0, 0.0)
        for i in 0..<steps {
            for j in 0..<steps {
                for k in 0..<steps {
                    let q = Vector3((Double(i) + 0.5) * h, (Double(j) + 0.5) * h, (Double(k) + 0.5) * h)
                    func slope(_ axis: Vector3) -> Double { (type.value(at: q + axis * d) - type.value(at: q - axis * d)) / (2 * d) }
                    let gradient = Vector3(slope(.unitX), slope(.unitY), slope(.unitZ)).length
                    let g = type.value(at: q)
                    maxGradient = max(maxGradient, gradient)
                    maxValue = max(maxValue, abs(g))
                    if abs(g) < shell { sum += gradient; count += 1 }
                }
            }
        }
        return (maxGradient, maxValue, sum / max(count, 1))
    }

    @Test(arguments: TPMSType.allCases)
    func theBoundsHoldAndTheWallScaleIsTheMeanGradientOnTheSurface(_ type: TPMSType) {
        let found = survey(type, steps: 64, shell: 0.04 * type.wallScale)
        #expect(found.maxGradient <= type.gradientBound, "\(type.name): |∇g| reaches \(found.maxGradient)")
        #expect(found.maxValue <= type.valueBound, "\(type.name): |g| reaches \(found.maxValue)")
        #expect(abs(found.shellGradient / type.wallScale - 1) < 0.05,
                "\(type.name): the mean |∇g| on the surface is \(found.shellGradient)")
    }

    // MARK: Cell size field

    @Test func theCellIndexUsesTheFieldsLocalValue() {
        // Cell size 4 + x / 10, as a field: the lattice coordinate at p is p / (4 + x / 10).
        let field = Field.add(.constant(4), .linearGradient(plane: Plane(origin: .zero, normal: .unitX, xAxis: .unitY), length: 10))
        let graded = Grading(field: field, range: 0...10, slope: 0.1)
        let region = BoundingBox(min: Vector3(-40, -40, -40), max: Vector3(40, 40, 40))
        let solid = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: graded),
                                                    thickness: .constant(0.4), region: region))
        let p = Vector3(6, 2.5, -3)
        let size = 4 + 6.0 / 10
        let q = Vector3(p.x / size, p.y / size, p.z / size) * Self.twoPi
        let expected = abs(TPMSType.gyroid.value(at: q) * size / (Self.twoPi * TPMSType.gyroid.wallScale)) - 0.2
        #expect(abs(solid.signedDistance(at: p) - expected) < 1e-12)
        // A field that is the same constant everywhere gives the same lattice as the plain number.
        let flat = Grading(field: .add(.constant(4.6), .constant(0)), range: 4.6...4.6, slope: 0)
        let plain = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: .constant(4.6)),
                                                    thickness: .constant(0.4), region: region))
        let viaField = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: flat),
                                                       thickness: .constant(0.4), region: region))
        #expect(abs(plain.signedDistance(at: p) - viaField.signedDistance(at: p)) < 1e-12)
    }

    @Test func aNegativeThicknessCountsAsZero() {
        let thickness = Grading(field: .add(.constant(-1), .constant(0)), range: -1...(-1), slope: 0)
        let solid = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeCells(size: .constant(Self.twoPi)),
                                                    thickness: thickness, region: Self.region))
        #expect(abs(solid.signedDistance(at: Vector3(Double.pi / 2, 0, 0)) - 1 / TPMSType.gyroid.wallScale) < 1e-12)
    }

    // MARK: Region, constants, recipe

    @Test func theLatticeIsCutOffAtTheRegionsBox() {
        let box = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 10, 10))
        let solid = lattice().withRegion(box)
        #expect(solid.bounds == box)
        #expect(solid.signedDistance(at: Vector3(14, 5, 5)) >= 4 - 1e-12, "outside the box the value is at least the distance to it")
        let inside = lattice(.gyroid, .sheet, cell: 8, thickness: 1).withRegion(box)
        let unclipped = lattice(.gyroid, .sheet, cell: 8, thickness: 1)
        #expect(abs(inside.signedDistance(at: Vector3(3, 4, 5)) - unclipped.signedDistance(at: Vector3(3, 4, 5))) < 1e-12)
    }

    @Test func aConstantLatticesLipschitzConstantIsItsSurfacesSteepestSlopeOverTheWallScale() {
        for type in TPMSType.allCases {
            let solid = lattice(type, .sheet, cell: 6, thickness: 1)
            #expect(abs(solid.lipschitz - max(1, type.gradientBound / type.wallScale)) < 1e-12, "\(type.name)")
        }
    }

    @Test func aGradedCellSizeRaisesTheConstant() {
        let flat = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.cells(6), thickness: .constant(1))
        let graded = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.gradedCell, thickness: .constant(1))
        #expect(graded.lipschitz > flat.lipschitz * 1.5,
                "the pattern moves with the size field: \(graded.lipschitz) against \(flat.lipschitz)")
        let thicker = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.cells(6), thickness: ImplicitFixtures.graded)
        #expect(abs(thicker.lipschitz - (flat.lipschitz + 0.025)) < 1e-12, "half the thickness field's slope")
    }

    @Test func theRecipeNamesTheTypeCellFormAndWall() {
        #expect(lattice(.gyroid, .sheet, cell: 8, thickness: 1.2).description == "gyroid(cell 8 mm, sheet, t = 1.2 mm)")
        #expect(lattice(.schwarzP, .network, cell: 5, thickness: 0).description == "schwarz p(cell 5 mm, network, t = 0 mm)")
        let stretched = lattice(.diamond, .sheet, cell: 8, thickness: 1, stretch: Vector3(1, 1, 4))
        #expect(stretched.description.hasPrefix("diamond(cell 8 mm, sheet, t = 1 mm, stretch 0.63 : 0.63 : 2.52)"))
    }

    @Test func aLatticeHoldsItsFieldsInItsByteEstimate() {
        let plain = lattice()
        let graded = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.gradedCell, thickness: ImplicitFixtures.noisy)
        #expect(graded.estimatedBytes > plain.estimatedBytes && plain.children.isEmpty && plain.nodeCount == 1)
    }
}

extension ImplicitSolid {
    /// A lattice with its region replaced (any other solid is returned unchanged).
    func withRegion(_ box: BoundingBox) -> ImplicitSolid {
        guard case .tpms(var lattice) = self else { return self }
        lattice.region = box
        return .tpms(lattice)
    }
}
