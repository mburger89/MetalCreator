import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

/// `OCCTShape.isValid`, OCCT's own checker, which the kernel runs on every blend (spec Errata (Kernel: invalid blends)).
struct ShapeValidityTests {
    func shape(_ solid: Solid) throws -> OCCTShape {
        try #require((solid.storage as? OCCTSolidStorage)?.shape)
    }

    /// Raw shim blend of the hexagon's upright edges, checked, with no kernel rule in between.
    func blendIsValid(_ flange: HexagonFlange, size: Double, chamfer: Bool) throws -> Bool {
        let union = try shape(flange.union)
        return try OCCTKernel.serialized { () throws -> Bool in
            try union.blended(edges: flange.uprightEdges, size: size, chamfer: chamfer).0.isValid
        }
    }

    @Test func theUnionAndItsSmallerBlendsAreValid() async throws {
        let flange = try await HexagonFlange.make(OCCTKernel())
        #expect(flange.uprightEdges.count == 4)
        let union = try shape(flange.union)
        #expect(OCCTKernel.serialized { union.isValid })
        #expect(try blendIsValid(flange, size: 2.5, chamfer: false))
        #expect(try blendIsValid(flange, size: 2.5, chamfer: true))
    }

    /// The probe's case: OCCT reports both blends done at 3 mm, but each solid has open wires and an unclosed shell.
    @Test(arguments: [false, true])
    func occtBuildsABrokenBlendOfTheUprightEdgesAt3mm(chamfer: Bool) async throws {
        let flange = try await HexagonFlange.make(OCCTKernel())
        #expect(try !blendIsValid(flange, size: 3, chamfer: chamfer))
    }
}
