import CreatorGeometry
import Foundation
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

    @Test func theConcurrentRunGivesTheSameResultAsTheLoop() async throws {
        let hollow = MeshFixtures.hollowCube(size: 10, wall: 0.2, divisions: 10)
        let loop = try ThinWallCheck.run(hollow, minimum: 0.4)
        let concurrent = try await ThinWallCheck.runConcurrently(hollow, minimum: 0.4)
        #expect(concurrent.triangles == loop.triangles && concurrent.places == loop.places && concurrent.thinnest == loop.thinnest)
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

    // MARK: Hits on the mesh's own fold (Errata D18)

    /// A vertex at the origin faces up (triangle 0). Triangle 1 shares the vertex's neighbours (1, 0, 0) and (0, 1, 0) and its third
    /// corner is placed so that the ray (x = y = 0) crosses it `foldDepth` below: the surface folding back on itself. Triangle 2 is a
    /// plate 0.2 mm down.
    func foldBesideTheVertex(foldDepth: Float) -> TriangleMesh {
        let positions: [SIMD3<Float>] = [
            [0, 0, 0], [1, 0, 0], [0, 1, 0], [-1, -1, -3 * foldDepth], [-1, -1, -0.2], [-1, 1, -0.2], [2, 0, -0.2],
        ]
        return TriangleMesh(positions: positions, triangles: [0, 1, 2, 1, 3, 2, 4, 5, 6])
    }

    /// Also the accepted limit of the rule: a real wall 0.01 mm thick whose far face is this triangle, on the vertex's neighbours, is
    /// indistinguishable from the fold and is not reported.
    @Test func aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall() throws {
        let wall = try #require(ThinWallCheck(foldBesideTheVertex(foldDepth: 0.01)).wall(behind: 0, limit: 0.4))
        #expect(abs(wall.distance - 0.2) < 1e-6 && wall.triangle == 2, "\(wall)")
    }

    @Test func aFoldBesideTheVertexFartherThanTheLimitIsTheWall() throws {
        let wall = try #require(ThinWallCheck(foldBesideTheVertex(foldDepth: 0.06)).wall(behind: 0, limit: 0.4))
        #expect(abs(wall.distance - 0.06) < 1e-6 && wall.triangle == 1, "\(wall)")
        #expect(ThinWallCheck.selfHitLimit == 0.05)
    }

    @Test func aPlateOutsideTheNeighbourhoodIsAWallHoweverClose() throws {
        // The same fold, but on vertices of its own: not the vertex's neighbours, so a real wall 0.01 mm thick.
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [-1, -1, -0.01], [-1, 1, -0.01], [2, 0, -0.01]]
        let wall = try #require(ThinWallCheck(TriangleMesh(positions: positions, triangles: Array(0..<6))).wall(behind: 0, limit: 0.4))
        #expect(abs(wall.distance - 0.01) < 1e-6 && wall.triangle == 1, "\(wall)")
    }

    /// A wedge 15 degrees either side of its edge: the faces are `2 x sin(15 degrees)` apart at distance x from the edge. The vertex
    /// 0.04 mm out on the top face looks across 0.02 mm at the bottom's first strip, which shares the edge's vertices with its
    /// neighbourhood: that is the mesh closing on the edge. The rows 0.3 and 0.6 mm out see walls of 0.18 and 0.36 mm along their rays,
    /// which are real and under the 0.4 mm minimum: the knife edge is still reported.
    @Test func aKnifeEdgeIsStillReportedAwayFromItsTip() throws {
        let wedge = MeshFixtures.wedge(topSteps: [0, 0.04, 0.3, 0.6, 1.2, 2], bottomSteps: [0, 0.3, 0.6, 1.2, 2], halfAngle: .pi / 12)
        let result = try ThinWallCheck.run(wedge, minimum: 0.4)
        #expect(result.places == 1, "one knife edge")
        let thinnest = try #require(result.thinnest)
        #expect(thinnest > ThinWallCheck.selfHitLimit, "the tip's own closing is not a wall: \(thinnest)")
        // 0.3 mm out the faces are 2 × 0.3 × sin 15° = 0.155 mm apart; the ray leaves the top face at 15° to the bottom's normal, 30° in all.
        #expect(abs(thinnest - 2 * 0.3 * sin(Double.pi / 12) / cos(Double.pi / 6)) < 1e-3, "the wall 0.3 mm out: \(thinnest)")
        #expect(result.triangles.count > 4, "the faces beside the thin rows are flagged")
    }
}
