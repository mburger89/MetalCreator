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
        // The faces of a cube meet at 90 degrees; the face beside a vertex near an edge is not the far side of a wall. (This passes
        // with or without `facingLimit`, the mesh being too clean to put an adjacent face in a ray's path; the filter is pinned by
        // `onlyAPlateFacingBackAtTheVertexIsTheFarSideOfAWall`.)
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

    /// A vertex at the origin faces up; two plates face back at it, the nearer 0.1 and the farther 0.3 below. Both are inside the minimum
    /// and both land in the one BVH leaf, so whichever the leaf lists last must not win: the wall is the nearer plate.
    @Test(arguments: [false, true]) func theWallIsTheNearerOfTwoPlatesInOneLeaf(nearerListedLast: Bool) throws {
        let top: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        let near: [SIMD3<Float>] = [[-1, -1, -0.1], [-1, 1, -0.1], [2, 0, -0.1]]
        let far: [SIMD3<Float>] = [[-2, -2, -0.3], [-2, 2, -0.3], [3, 0, -0.3]]
        let plates = nearerListedLast ? [far, near] : [near, far]
        let mesh = TriangleMesh(positions: top + plates.flatMap { $0 }, triangles: Array(0..<9))
        let nearIndex = nearerListedLast ? 2 : 1
        let wall = try #require(ThinWallCheck(mesh).wall(behind: 0, limit: 0.4))
        #expect(abs(wall.distance - 0.1) < 1e-6, "distance \(wall.distance)")
        #expect(wall.triangle == nearIndex, "joined to triangle \(wall.triangle), the nearer plate is \(nearIndex)")
    }

    /// A vertex at the origin faces up; a plate 0.1 below lies in its ray. Only a plate that faces back at the vertex (a normal within
    /// 60 degrees of straight down) is the far side of a wall: one that faces the same way, or sits at 90 degrees, is not. This is what
    /// `facingLimit` is for; with the limit off, the first two arguments find a wall.
    @Test(arguments: zip([[0.0, 0, 1], [0.954, 0, -0.3], [0.8, 0, -0.6], [0, 0, -1]], [false, false, true, true]))
    func onlyAPlateFacingBackAtTheVertexIsTheFarSideOfAWall(_ direction: [Double], _ isWall: Bool) throws {
        let raw = SIMD3<Double>(direction[0], direction[1], direction[2])
        let normal = raw / raw.length
        let tangent = SIMD3<Double>(0, 1, 0)
        let across = normal.cross(tangent)
        let centre = SIMD3<Double>(0, 0, -0.1)
        let corners = [centre - tangent * 4 - across * 4, centre + tangent * 4 - across * 4, centre + across * 4]
        // Counter-clockwise seen from along the normal, so the face's normal is the one under test.
        let wound = (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0 ? corners : corners.reversed()
        let top: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        let mesh = TriangleMesh(positions: top + wound.map { SIMD3<Float>($0) }, triangles: Array(0..<6))
        let wall = ThinWallCheck(mesh).wall(behind: 0, limit: 0.4)
        #expect((wall != nil) == isWall, "plate normal \(normal): \(String(describing: wall))")
    }
}
