import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Check Thin Walls (implicit spec §4.6, §7): a 0.2 mm wall is found, a sound part is not.
struct ThinWallCheckTests {
    @Test func aWallOfAFifthOfAMillimetreIsFoundWhereverTheCubeHasOne() throws {
        let hollow = MeshFixtures.hollowCube(size: 10, wall: 0.2, divisions: 10)
        let result = try ThinWallCheck.run(hollow, minimum: 0.4)
        #expect(abs((result.thinnest ?? 0) - 0.2) < 1e-6, "thinnest \(String(describing: result.thinnest))")
        #expect(result.places == 1, "the two sides of one wall are one place; got \(result.places)")
        #expect(result.triangles.count == hollow.triangleCount, "every face of both shells has a thin wall behind it")
    }

    @Test func aWallThickerThanTheMinimumIsLeftAlone() throws {
        let hollow = MeshFixtures.hollowCube(size: 10, wall: 0.5, divisions: 10)
        let result = try ThinWallCheck.run(hollow, minimum: 0.4)
        #expect(result.triangles.isEmpty && result.places == 0 && result.thinnest == nil)
    }

    @Test func aSolidCubeAndASphereHaveNoThinWalls() throws {
        let cube = MeshFixtures.subdividedCube(divisions: 8)
        #expect(try ThinWallCheck.run(cube, minimum: 0.4).places == 0)
        #expect(try ThinWallCheck.run(MeshFixtures.sphereMesh(radius: 5, subdivisions: 3), minimum: 0.4).places == 0)
    }

    @Test func aSharpCornerIsNotAWall() throws {
        // The faces of a cube meet at 90 degrees; the face beside a vertex near an edge is not the far side of a wall.
        let small = MeshFixtures.subdividedCube(divisions: 20)
        let scaled = TriangleMesh(positions: small.positions.map { $0 * 2 }, triangles: small.triangles)
        #expect(try ThinWallCheck.run(scaled, minimum: 0.4).places == 0)
    }

    @Test func twoThinPlatesApartAreTwoPlaces() throws {
        let one = MeshFixtures.hollowCube(size: 10, wall: 0.2, divisions: 6)
        let shift = SIMD3<Float>(30, 0, 0)
        let both = TriangleMesh(positions: one.positions + one.positions.map { $0 + shift },
                                triangles: one.triangles + one.triangles.map { $0 + UInt32(one.positions.count) })
        let result = try ThinWallCheck.run(both, minimum: 0.4)
        #expect(result.places == 2)
    }

    @Test func aMeshFromTheMesherHasTheWallItWasGiven() async throws {
        // A ball with a hollow centre: a shell 0.3 mm thick, meshed at 0.1 mm.
        let shell = ImplicitSolid.shell(.sphere(radius: 2), thickness: .constant(0.3), side: .inward)
        let mesh = try await ImplicitMesher(evaluator: CPUBatchEvaluator(shell)).mesh(shell, resolution: 0.1, quality: .export)
        let result = try ThinWallCheck.run(mesh, minimum: 0.45)
        #expect(result.places == 1 && result.triangles.count > mesh.triangleCount / 2)
        let thinnest = try #require(result.thinnest)
        #expect(abs(thinnest - 0.3) < 0.05, "thinnest \(thinnest)")
        #expect(try ThinWallCheck.run(mesh, minimum: 0.2).places == 0)
    }

    @Test func aMeshOfABoxFromTheMesherHasNoFalsePlacesAtItsEdges() async throws {
        let box = ImplicitSolid.box(halfSize: Vector3(3, 2, 2), cornerRadius: 0)
        let mesh = try await ImplicitMesher(evaluator: CPUBatchEvaluator(box)).mesh(box, resolution: 0.15, quality: .export)
        #expect(try ThinWallCheck.run(mesh, minimum: 0.4).places == 0)
    }

    @Test func anEmptyMeshOrABadMinimumFindsNothing() throws {
        let empty = TriangleMesh(positions: [], triangles: [])
        #expect(try ThinWallCheck.run(empty, minimum: 0.4).places == 0)
        #expect(try ThinWallCheck.run(MeshFixtures.cube, minimum: .nan).places == 0)
        #expect(try ThinWallCheck.run(MeshFixtures.cube, minimum: 0).places == 0)
    }
}
