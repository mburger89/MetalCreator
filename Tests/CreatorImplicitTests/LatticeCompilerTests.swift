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
        #expect(try source(a).contains("tpmsLattice(p,"))
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
        #expect(try source(a).contains("strutLattice(e,"))
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
}
