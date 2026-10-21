import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// What the compiler generates for the lattices (implicit spec §4.1): the source depends on the lattice's shape, and every number, type
/// and form is in a buffer, so editing one never recompiles. (Every fixture also compiles and agrees with the CPU: `GPUAgreementTests`
/// runs `LatticeFixtures` with the rest.)
struct LatticeCompilerTests {
    func source(_ solid: ImplicitSolid) throws -> String { try ImplicitCompiler.compile(solid).source }

    @Test func aTPMSsTypeFormAndNumbersAreNotInTheSource() throws {
        let a = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.cells(8), thickness: .constant(1))
        let b = LatticeFixtures.tpms(.lidinoid, .network, cells: LatticeFixtures.cells(3, stretch: Vector3(1, 2, 3)),
                                     thickness: .constant(0.2))
        #expect(try source(a) == source(b))
        #expect(try source(a).contains("tpmsBody(p,"))
    }

    @Test func aGradedCellSizeIsAnotherShapeFromAConstantOne() throws {
        let plain = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.cells(6), thickness: .constant(1))
        let graded = LatticeFixtures.tpms(.gyroid, .sheet, cells: LatticeFixtures.gradedCell, thickness: .constant(1))
        #expect(try source(plain) != source(graded))
    }

    @Test func theTPMSsNumbersAreInTheParameterBuffers() throws {
        let program = try ImplicitCompiler.compile(
            LatticeFixtures.tpms(.diamond, .network, cells: LatticeFixtures.cells(5), thickness: .constant(0.5)))
        // cell, thickness, stretch (3), the wall scale, then the region's centre and half size (3 + 3).
        #expect(program.parameters.count == 1 + 1 + 3 + 1 + 6)
        #expect(program.integers == [Int32(TPMSType.diamond.rawValue), Int32(TPMSForm.network.rawValue)])
    }

    @Test func aStrutLatticesCellKindAndNumbersAreNotInTheSource() throws {
        let a = LatticeFixtures.struts(.cubic, cells: LatticeFixtures.cells(6), radius: .constant(0.5))
        let b = LatticeFixtures.struts(.kelvin, cells: LatticeFixtures.cells(2, stretch: Vector3(3, 1, 1)), radius: .constant(0.1),
                                       blend: 0.4)
        #expect(try source(a) == source(b))
        #expect(try source(a).contains("strutBody(e,"))
    }

    @Test func theStrutsGoToThePoolSixFloatsEach() throws {
        let program = try ImplicitCompiler.compile(LatticeFixtures.struts(.octet, cells: LatticeFixtures.cells(6), radius: .constant(0.5)))
        #expect(program.pool.count == 24 * 6)
        #expect(program.integers == [0, 24], "where the struts start in the pool, and how many there are")
        let after = try ImplicitCompiler.compile(.union([
            .baked(BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }, label: "a"),
            LatticeFixtures.struts(.bcc, cells: LatticeFixtures.cells(6), radius: .constant(0.5)),
        ], blend: .constant(0)))
        #expect(after.pool.count == 512 + 1 + 8 * 6)
        #expect(after.integers.suffix(2) == [513, 8], "the struts follow the baked block in the pool")
    }

    @Test func aVoronoiLatticesSeedsAndFormAreNotInTheSource() throws {
        let a = LatticeFixtures.voronoi(LatticeFixtures.seeds(10, seed: 1), .struts, thickness: .constant(1))
        let b = LatticeFixtures.voronoi(LatticeFixtures.seeds(500, seed: 9), .foam, thickness: .constant(0.2))
        #expect(try source(a) == source(b))
        #expect(try source(a).contains("voronoiBody(e,"))
    }

    @Test func theSeedsGoToThePoolAndTheGridToTheTables() throws {
        let points = LatticeFixtures.seeds(40, seed: 4)
        let solid = LatticeFixtures.voronoi(points, .foam, thickness: .constant(0.5))
        let program = try ImplicitCompiler.compile(solid)
        guard case .voronoi(let lattice) = solid else { Issue.record("not a Voronoi lattice"); return }
        let seeds = lattice.seeds
        #expect(program.pool.count == 40 * 3)
        #expect(program.tables == seeds.starts + seeds.entries)
        let grid = seeds.counts.map { Int32($0) }
        #expect(program.integers == [0, 0, Int32(seeds.starts.count)] + grid + [Int32(VoronoiForm.foam.rawValue)])
        // The thickness comes first, then the grid's corner and cell size.
        let corner = [seeds.origin.x, seeds.origin.y, seeds.origin.z, seeds.radius].map { Float($0) }
        #expect(Array(program.parameters[1..<5]) == corner)
    }

    // MARK: Mappings

    @Test func aMappingIsAnotherShapeAndItsNumbersAreInTheBuffers() throws {
        let gyroid = LatticeFixtures.tpmsAll[0].solid
        let straight = try source(gyroid)
        let cylinder = try source(LatticeFixtures.mapped(gyroid, LatticeFixtures.cylinder(through: LatticeFixtures.crossing, cell: 8)))
        let moved = try source(LatticeFixtures.mapped(gyroid, LatticeFixtures.cylinder(through: LatticeFixtures.beside, cell: 5)))
        let sphere = try source(LatticeFixtures.mapped(gyroid, LatticeFixtures.sphere(at: LatticeFixtures.crossing, cell: 8)))
        #expect(straight != cylinder && cylinder != sphere)
        #expect(cylinder == moved, "another axis or radius is only other numbers")
        #expect(cylinder.contains("mapCylindrical(p,") && cylinder.contains("singularCylindrical(p,") && cylinder.contains("mappingJoin("))
        #expect(sphere.contains("mapSpherical(p,") && !sphere.contains("mapCylindrical(p,"))
        #expect(!straight.contains("mapCylindrical(p,") && !straight.contains("mappingJoin(v"), "Straight reads the point itself")
    }

    @Test func aFaceMappingIsOneShapeWhateverTheFaceAndItsChartsBlocksAreRegistered() throws {
        let gyroid = LatticeFixtures.tpmsAll[0].solid
        let face = LatticeFixtures.mapped(gyroid, LatticeFixtures.face(cell: 8))
        let program = try ImplicitCompiler.compile(face)
        for call in ["mapFace(e,", "bakedChannel(e,", "mappingJoin("] { #expect(program.source.contains(call), "\(call)") }
        #expect(try source(face) == source(LatticeFixtures.mapped(gyroid, LatticeFixtures.face(cell: 5))), "only the numbers differ")
        #expect(try source(face) != source(LatticeFixtures.mapped(gyroid, LatticeFixtures.cylinder(through: .zero, cell: 8))))
        // The cosine and sine of the angle, the height, the depth and the singular distance: five blocks, each stored once.
        let chart = LatticeFixtures.cylinderChart
        #expect(chart.allBlocks.count == 5)
        #expect(program.pool.count >= chart.allBlocks.reduce(0) { $0 + $1.pool.count })
    }

    @Test func aMappedLatticeKeepsTheRegionCutAtTheRealPoint() throws {
        let program = try ImplicitCompiler.compile(LatticeFixtures.mappedAll[0].solid)
        #expect(program.source.contains("regionDistance(p,"), "the box is a box of the world, not of the lattice coordinates")
    }
}
