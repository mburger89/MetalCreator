import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The strut lattice (implicit spec §3.4, §7): the six unit cells, hand-worked distances, the window of 27 cells against a brute-force
/// search, the joint blend and the constants.
struct StrutLatticeTests {
    static let region = BoundingBox(min: Vector3(-60, -60, -60), max: Vector3(60, 60, 60))

    func lattice(_ cell: StrutCell, size: Double = 10, radius: Double = 1, blend: Double = 0,
                 stretch: Vector3 = Vector3(1, 1, 1)) -> ImplicitSolid {
        .struts(StrutLattice(cell: cell, cells: LatticeFixtures.cells(size, stretch: stretch), radius: .constant(radius), blend: blend,
                             region: Self.region))
    }

    func value(_ solid: ImplicitSolid, _ point: Vector3) -> Double { solid.signedDistance(at: point) }

    // MARK: The cells

    /// Each cell, how many struts it has and how long each is (in cells).
    static let shapes: [(cell: StrutCell, count: Int, length: Double)] = [
        (.cubic, 3, 1), (.bcc, 8, 0.75.squareRoot()), (.fcc, 12, 0.5.squareRoot()), (.octet, 24, 0.5.squareRoot()),
        (.kelvin, 24, 0.125.squareRoot()), (.diamond, 16, 0.1875.squareRoot()),
    ]

    @Test(arguments: shapes.indices)
    func eachCellHasItsStrutCountAndLength(_ index: Int) {
        let (cell, count, length) = Self.shapes[index]
        let struts = cell.struts
        #expect(struts.count == count)
        #expect(struts.allSatisfy { abs(($0.end - $0.start).length - length) < 1e-12 }, "\(cell.name): every strut has length \(length)")
    }

    @Test(arguments: StrutCell.allCases)
    func aStrutBelongsToTheCellItsMidpointIsIn(_ cell: StrutCell) {
        for strut in cell.struts {
            let middle = (strut.start + strut.end) * 0.5
            #expect(middle.x >= -1e-12 && middle.x < 1 && middle.y >= -1e-12 && middle.y < 1 && middle.z >= -1e-12 && middle.z < 1)
            let coordinates = [strut.start, strut.end].flatMap { [$0.x, $0.y, $0.z] }
            #expect(coordinates.allSatisfy { $0 >= -StrutCell.spill - 1e-12 && $0 <= 1 + StrutCell.spill + 1e-12 })
        }
    }

    @Test(arguments: StrutCell.allCases)
    func theMidpointOfEveryStrutIsOnTheLattice(_ cell: StrutCell) {
        let solid = lattice(cell)
        for strut in cell.struts {
            let middle = (strut.start + strut.end) * 0.5 * 10
            #expect(abs(value(solid, middle) + 1) < 1e-9, "\(cell.name): a point on a strut is the radius inside")
        }
    }

    // MARK: Distances

    @Test func aCubicLatticeIsTheDistanceToTheAxisLinesThroughEachCorner() {
        let solid = lattice(.cubic)
        #expect(abs(value(solid, Vector3(3, 0.5, 0)) + 0.5) < 1e-12)
        #expect(abs(value(solid, Vector3(5, 5, 5)) - (50.0.squareRoot() - 1)) < 1e-12, "the cell centre is √50 from the nearest edge")
        #expect(abs(value(solid, Vector3(3, 2, 0)) - 1) < 1e-12)
        #expect(abs(value(solid, Vector3(-2, 0, 0)) + 1) < 1e-12 && abs(value(solid, Vector3(10, 10, 4)) + 1) < 1e-12)
    }

    @Test func theValueIsCappedWhereTheWindowStopsSeeing() {
        // Cell edges 16, 16 and 2 mm: the middle of a big face is 8.06 mm from the nearest strut, but the window sees 0.85 × 2 mm.
        let flat = lattice(.cubic, size: 8, radius: 0, stretch: Vector3(8, 8, 1))
        #expect(abs(value(flat, Vector3(8, 8, 1)) - 1.7) < 1e-12)
        #expect(abs(value(lattice(.cubic, size: 10, radius: 0), Vector3(5, 5, 5)) - 50.0.squareRoot()) < 1e-12, "under the cap")
    }

    @Test(arguments: StrutCell.allCases)
    func theWindowOf27CellsFindsTheNearestStrut(_ cell: StrutCell) {
        let solid = lattice(cell, size: 8, radius: 0)
        let random = SeededRandom(seed: 5, stream: 11)
        for index in 0..<300 {
            let point = Vector3(random.unit(at: 3 * index) * 40 - 20, random.unit(at: 3 * index + 1) * 40 - 20,
                                random.unit(at: 3 * index + 2) * 40 - 20)
            var nearest = Double.infinity
            let (cx, cy, cz) = (floor(point.x / 8), floor(point.y / 8), floor(point.z / 8))
            for dz in -3...3 {
                for dy in -3...3 {
                    for dx in -3...3 {
                        let base = Vector3(cx + Double(dx), cy + Double(dy), cz + Double(dz))
                        for strut in cell.struts {
                            nearest = min(nearest, CPUEvaluation.segmentDistance(point, (base + strut.start) * 8, (base + strut.end) * 8))
                        }
                    }
                }
            }
            #expect(abs(value(solid, point) - min(nearest, 0.85 * 8)) < 1e-9, "\(cell.name) at \(point)")
        }
    }

    @Test func aStretchedCellMovesTheStrutsAndKeepsTheirRadius() {
        let solid = lattice(.cubic, size: 8, radius: 0.5, stretch: Vector3(1, 1, 8))
        // The stretch is scaled to geometric mean 1 (8 ^ (1/3) = 2), so the cell edges are 4, 4 and 32 mm.
        #expect(abs(value(solid, Vector3(0.2, 0, 20)) + 0.3) < 1e-12, "a strut along z runs to z = 32")
        #expect(abs(value(solid, Vector3(2, 0.3, 0)) + 0.2) < 1e-12, "a strut along x runs to x = 4")
    }

    // MARK: Joints

    @Test func theBlendRoundsTheJointsAndLeavesTheStrutsAlone() {
        let sharp = lattice(.cubic, radius: 1, blend: 0), rounded = lattice(.cubic, radius: 1, blend: 0.8)
        #expect(value(rounded, .zero) < value(sharp, .zero) - 0.2, "six struts meet at a node")
        #expect(abs(value(rounded, Vector3(5, 0, 0)) - value(sharp, Vector3(5, 0, 0))) < 1e-12, "mid-strut nothing else is near")
    }

    @Test func aNegativeRadiusCountsAsZero() {
        let radius = Grading(field: .add(.constant(-1), .constant(0)), range: -1...(-1), slope: 0)
        let solid = ImplicitSolid.struts(StrutLattice(cell: .cubic, cells: LatticeFixtures.cells(10), radius: radius, blend: 0,
                                                      region: Self.region))
        #expect(abs(value(solid, Vector3(3, 2, 0)) - 2) < 1e-12)
    }

    // MARK: Region, constants, recipe

    @Test func theLatticeIsCutOffAtTheRegionsBox() {
        let box = BoundingBox(min: .zero, max: Vector3(10, 10, 10))
        let solid = ImplicitSolid.struts(StrutLattice(cell: .octet, cells: LatticeFixtures.cells(4), radius: .constant(0.5), blend: 0,
                                                      region: box))
        #expect(solid.bounds == box)
        #expect(solid.signedDistance(at: Vector3(15, 5, 5)) >= 5 - 1e-12)
    }

    @Test func aFixedCellSizeIsExactAndAGradedOneRaisesTheConstant() {
        #expect(lattice(.kelvin).lipschitz == 1)
        let graded = LatticeFixtures.struts(.bcc, cells: LatticeFixtures.gradedCell, radius: .constant(0.5))
        #expect(graded.lipschitz > 1.5)
        let thicker = LatticeFixtures.struts(.bcc, cells: LatticeFixtures.cells(6), radius: ImplicitFixtures.graded)
        #expect(abs(thicker.lipschitz - 1.05) < 1e-12, "plus the radius field's slope")
    }

    @Test func theRecipeNamesTheCellRadiusAndJoint() {
        #expect(lattice(.octet, size: 6, radius: 0.4).description == "octet(cell 6 mm, r = 0.4 mm)")
        #expect(lattice(.bcc, size: 6, radius: 0.4, blend: 0.2).description == "bcc(cell 6 mm, r = 0.4 mm, blend 0.2 mm)")
    }
}
