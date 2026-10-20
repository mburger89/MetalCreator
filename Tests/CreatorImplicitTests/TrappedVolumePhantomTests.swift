import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The phantom void of a sheet meeting a slab tangentially (implicit spec Errata M5 and D18).
struct TrappedVolumePhantomTests {
    /// What the lightweight bracket is made of, small: an 8 mm cube with a 1.5 mm skin, a gyroid sheet 1.2 mm thick (cell 10 mm) filling
    /// it and joined to the skin by a 1 mm smooth union, meshed at 0.6 mm. The sheet meets the skin's inner face tangentially in thin
    /// wedges, narrower than the cell, and there the mesh overlaps itself. The skin closes the two gyroid channels, so there are two real
    /// voids; at this size the pseudonormal sign finds a third, of 110 cells, that is solid material.
    static func skinnedSheet(half: Double = 4, cell: Double = 10, offset: Vector3 = .zero,
                             resolution: Double = 0.6) async throws -> (solid: ImplicitSolid, mesh: TriangleMesh) {
        let box = ImplicitSolid.box(halfSize: Vector3(half, half, half), cornerRadius: 0)
        let region = offset == .zero ? box : .moved(box, RigidMove(origin: offset, xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let lattice = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeFixtures.cells(cell),
                                                      thickness: .constant(1.2), region: region.bounds))
        let wall = ImplicitSolid.shell(region, thickness: .constant(1.5), side: .inward)
        let inside = ImplicitSolid.offset(region, distance: .constant(-1.5))
        let solid = ImplicitSolid.union([wall, .intersect([lattice, inside], blend: .constant(0))], blend: .constant(1))
        let mesh = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .export)
        return (solid, mesh)
    }

    func distances(_ mesh: TriangleMesh) throws -> SignedDistanceMesh {
        try SignedDistanceMesh(positions: (0..<mesh.vertexCount).map { mesh.point($0) }, indices: mesh.triangles)
    }

    /// The sizes of the voids, and the largest `signedDistance` of the part at any cell centre of any void (negative: inside the part).
    func voids(of mesh: TriangleMesh, in solid: ImplicitSolid, robust: Bool) throws -> [(cells: Int, deepestInsidePart: Double)] {
        let measure = try distances(mesh)
        let bounds = try #require(mesh.bounds)
        let found: EnclosedVoids
        let grid: OccupancyGrid
        if robust {
            (grid, found) = try TrappedVolumeCheck.findVoids(in: measure, bounds: bounds)
        } else {
            // The classifier before D18: the pseudonormal sign, every cell asked.
            var plain = OccupancyGrid(bounds: bounds)
            try plain.fill { points in points.map { measure.signedDistance(at: $0) } }
            grid = plain
            found = try EnclosedVoids(plain)
        }
        return found.voids.map { cells in
            (cells.count, cells.map { solid.signedDistance(at: grid.center(of: Int($0))) }.min() ?? 0)
        }
    }

    @Test func aWedgeOfSheetOnSkinIsNotAVoid() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        let found = try voids(of: mesh, in: solid, robust: true)
        #expect(found.count == 2, "the two channels the skin closes, and no phantom: \(found.map(\.cells))")
        #expect(found.allSatisfy { $0.cells > 1000 }, "\(found.map(\.cells))")
        #expect(try TrappedVolumeCheck.run(mesh).voidCount == 2)
    }

    @Test func everyVoidItFindsIsAirOutsideThePart() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        // The channel's air is outside the part by the field itself: no void cell centre is inside it.
        for void in try voids(of: mesh, in: solid, robust: true) { #expect(void.deepestInsidePart > 0, "\(void)") }
    }

    #if os(macOS)
    /// Pins the fixture: the pseudonormal sign still finds a void here that is solid material (the field is at most 0 at all its cell
    /// centres). If this fails, the mesher changed and the fixture no longer reproduces the phantom; find a size that does. Only that a
    /// phantom exists is pinned, not how many cells or voids: the wedge is narrower than a mesh cell, so its size follows the mesher's
    /// last-bit arithmetic, and the fixture was measured on macOS (arm64) only, so the Linux and Windows jobs do not run this test.
    @Test func thePseudonormalSignFindsAPhantomVoidInTheSameMesh() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        let found = try voids(of: mesh, in: solid, robust: false)
        #expect(found.contains { $0.deepestInsidePart <= 0 }, "\(found)")
    }
    #endif
}
