import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Check Trapped Volumes (implicit spec §4.6, §7): a sealed internal void is found and its walls highlighted.
struct TrappedVolumeCheckTests {
    @Test func aSealedVoidIsFoundAndItsWallsAreTheOnesThatLookIntoIt() throws {
        let hollow = MeshFixtures.hollowCube(size: 10, wall: 1, divisions: 8)
        let outerCount = 6 * 8 * 8 * 2
        let result = try TrappedVolumeCheck.run(hollow)
        #expect(result.voidCount == 1)
        #expect(result.triangles.count == hollow.triangleCount - outerCount, "the void's own faces, and no others")
        #expect(result.triangles.allSatisfy { $0 >= outerCount })
        #expect(result.cell == 10.0 / 32, "the grid's cell is reported for the node's fact")
    }

    @Test func twoVoidsAreCounted() throws {
        let part = MeshFixtures.cubeWithVoids(size: 20, divisions: 4, voids: [SIMD4(2, 2, 2, 5), SIMD4(11, 11, 11, 6)])
        #expect(try TrappedVolumeCheck.run(part).voidCount == 2)
    }

    @Test func aSolidPartHasNoVoids() throws {
        #expect(try TrappedVolumeCheck.run(MeshFixtures.subdividedCube(divisions: 4)).voidCount == 0)
        #expect(try TrappedVolumeCheck.run(MeshFixtures.sphereMesh(radius: 5, subdivisions: 3)).voidCount == 0)
    }

    @Test func aVoidTooSmallForTheGridIsNotFound() throws {
        let part = MeshFixtures.cubeWithVoids(size: 10, divisions: 4, voids: [SIMD4(4.9, 4.9, 4.9, 0.2)])
        #expect(try TrappedVolumeCheck.run(part).voidCount == 0)
    }

    @Test func aVoidInsideAThinWallIsStillSealed() throws {
        // The wall is 0.2 mm and the cells are 0.31 mm: the wall must not be a gap in the grid.
        #expect(try TrappedVolumeCheck.run(MeshFixtures.hollowCube(size: 10, wall: 0.2, divisions: 10)).voidCount == 1)
    }

    @Test func aMeshThatIsNotClosedHasNoInside() {
        let open = MeshFixtures.patch(divisions: 4)
        #expect(throws: MeshDistanceError.notClosed) { try TrappedVolumeCheck.run(open) }
    }

    @Test func aCavityInsideAMeshedBallIsFound() async throws {
        let ball = ImplicitSolid.subtract([.sphere(radius: 3), .sphere(radius: 1.5)], blend: .constant(0))
        let mesh = try await ImplicitMesher(evaluator: CPUBatchEvaluator(ball)).mesh(ball, resolution: 0.2, quality: .export)
        #expect(MeshTopology(mesh).eulerCharacteristic == 4, "two closed shells")
        let result = try TrappedVolumeCheck.run(mesh)
        #expect(result.voidCount == 1 && !result.triangles.isEmpty)
        let flagged = Set(result.triangles)
        for index in flagged { #expect(mesh.corners(of: index).0.length < 1.7, "only the cavity's wall is highlighted") }
    }

    @Test func anEmptyMeshHasNoVoids() throws {
        #expect(try TrappedVolumeCheck.run(TriangleMesh(positions: [], triangles: [])).voidCount == 0)
    }
}
