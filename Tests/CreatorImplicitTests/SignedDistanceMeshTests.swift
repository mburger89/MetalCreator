import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The signed distance to a closed mesh (implicit spec §4.4, §7): hand-worked values, welding, refusal of open meshes, and the BVH
/// against a brute-force search.
struct SignedDistanceMeshTests {
    static func vectors(_ mesh: TriangleMesh) -> [Vector3] { (0..<mesh.vertexCount).map { mesh.point($0) } }

    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    func cube() throws -> SignedDistanceMesh {
        try SignedDistanceMesh(positions: Self.vectors(MeshFixtures.cube), indices: MeshFixtures.cube.triangles)
    }

    @Test func aCubeIsMeasuredToItsFacesEdgesAndCorners() throws {
        let cube = try cube()
        #expect(near(cube.signedDistance(at: Vector3(0.5, 0.5, 0.5)), -0.5))
        #expect(near(cube.signedDistance(at: Vector3(2, 0.5, 0.5)), 1))
        #expect(near(cube.signedDistance(at: Vector3(2, 2, 0.5)), 2.0.squareRoot()), "past an edge")
        #expect(near(cube.signedDistance(at: Vector3(2, 2, 2)), 3.0.squareRoot()), "past a corner")
        #expect(near(cube.signedDistance(at: Vector3(0.9, 0.5, 0.5)), -0.1))
        #expect(near(cube.signedDistance(at: Vector3(-1, -1, -1)), 3.0.squareRoot()))
        #expect(cube.signedDistance(at: Vector3(1, 0.5, 0.5)) == 0)
    }

    @Test func theSignIsRightNextToEdgesAndCornersFromBothSides() throws {
        let cube = try cube()
        // Just inside and just outside an edge and a corner, where a plain "nearest face" sign would be unreliable.
        #expect(cube.signedDistance(at: Vector3(0.99, 0.99, 0.5)) < 0)
        #expect(cube.signedDistance(at: Vector3(1.01, 1.01, 0.5)) > 0)
        #expect(cube.signedDistance(at: Vector3(0.99, 0.99, 0.99)) < 0)
        #expect(cube.signedDistance(at: Vector3(1.01, 1.01, 1.01)) > 0)
        #expect(cube.signedDistance(at: Vector3(1.01, 0.99, 0.5)) > 0 && cube.signedDistance(at: Vector3(0.99, 1.01, 0.5)) > 0)
    }

    @Test func aSoupOfPerFaceVerticesGivesTheSameDistances() throws {
        let soup = MeshFixtures.cubeSoup
        let welded = try SignedDistanceMesh(positions: soup.positions, indices: soup.indices)
        let reference = try cube()
        #expect(welded.triangleCount == 12)
        for point in [Vector3(0.5, 0.5, 0.5), Vector3(2, 2, 2), Vector3(-0.3, 0.4, 0.9), Vector3(0.2, 0.1, 0.05)] {
            #expect(near(welded.signedDistance(at: point), reference.signedDistance(at: point)))
        }
    }

    @Test func anOpenMeshIsRefused() {
        var triangles = MeshFixtures.cube.triangles
        triangles.removeLast(3)
        #expect(throws: MeshDistanceError.notClosed) {
            try SignedDistanceMesh(positions: Self.vectors(MeshFixtures.cube), indices: triangles)
        }
        #expect(MeshDistanceError.notClosed.userMessage == "This solid isn't closed, so inside and outside are undefined.")
    }

    @Test func aCollinearSliverClosesTheSurfaceItSitsInAndAddsNoDistance() throws {
        // The bottom face's edge 0-1 gets a midpoint 8 on its far side, and the sliver (0, 1, 8), three distinct points on a line, holds
        // the two halves to the unsplit face: the surface is closed, and the sliver has no area to measure from.
        var positions = Self.vectors(MeshFixtures.cube)
        positions.append(Vector3(0.5, 0, 0))
        var triangles = MeshFixtures.cube.triangles
        let neighbour = try #require(stride(from: 0, to: triangles.count, by: 3).first { Array(triangles[$0..<$0 + 3]) == [0, 1, 5] })
        triangles.replaceSubrange(neighbour..<neighbour + 3, with: [0, 8, 5, 8, 1, 5])
        triangles += [0, 1, 8]
        let mesh = try SignedDistanceMesh(positions: positions, indices: triangles)
        #expect(mesh.triangleCount == 13, "the sliver is not kept")
        #expect(near(mesh.signedDistance(at: Vector3(0.5, 0.5, 0.5)), -0.5))
        #expect(near(mesh.signedDistance(at: Vector3(2, 0.5, 0.5)), 1))
    }

    @Test func aFlippedFaceIsRefused() {
        var triangles = MeshFixtures.cube.triangles
        triangles.swapAt(1, 2)
        #expect(throws: MeshDistanceError.notClosed) {
            try SignedDistanceMesh(positions: Self.vectors(MeshFixtures.cube), indices: triangles)
        }
    }

    @Test func anEmptyMeshIsRefused() {
        #expect(throws: MeshDistanceError.notClosed) { try SignedDistanceMesh(positions: [], indices: []) }
    }

    @Test func aSphereMeshIsCloseToASphere() throws {
        let sphere = MeshFixtures.sphere(radius: 5, subdivisions: 3)
        let mesh = try SignedDistanceMesh(positions: sphere.positions, indices: sphere.indices)
        let random = SeededRandom(seed: 5, stream: 1)
        for index in 0..<300 {
            let point = Vector3(random.unit(at: 3 * index) * 16 - 8, random.unit(at: 3 * index + 1) * 16 - 8,
                                random.unit(at: 3 * index + 2) * 16 - 8)
            // 512 triangles whose edges run up to 1.2 mm: the facets sag up to about 0.07 mm inside the sphere.
            #expect(abs(mesh.signedDistance(at: point) - (point.length - 5)) < 0.1, "at \(point)")
        }
    }

    @Test func theBVHMatchesABruteForceSearch() throws {
        let sphere = MeshFixtures.sphere(radius: 5, subdivisions: 2)
        let mesh = try SignedDistanceMesh(positions: sphere.positions, indices: sphere.indices)
        let random = SeededRandom(seed: 6, stream: 1)
        for index in 0..<200 {
            let point = Vector3(random.unit(at: 3 * index) * 14 - 7, random.unit(at: 3 * index + 1) * 14 - 7,
                                random.unit(at: 3 * index + 2) * 14 - 7)
            var best = Double.infinity
            for base in stride(from: 0, to: sphere.indices.count, by: 3) {
                let corners = (0..<3).map { sphere.positions[Int(sphere.indices[base + $0])] }
                best = min(best, Self.distance(from: point, toTriangle: corners))
            }
            #expect(abs(abs(mesh.signedDistance(at: point)) - best) < 1e-9, "at \(point)")
        }
    }

    /// The distance to a triangle: to its face when the projection falls inside, else to the nearest edge.
    static func distance(from p: Vector3, toTriangle t: [Vector3]) -> Double {
        let normal = (t[1] - t[0]).cross(t[2] - t[0])
        let area = normal.length
        if let unit = normal.normalized {
            let projected = p - unit * (p - t[0]).dot(unit)
            let inside = (0..<3).allSatisfy { side in
                (t[(side + 1) % 3] - t[side]).cross(projected - t[side]).dot(normal) >= -1e-12 * area
            }
            if inside { return abs((p - t[0]).dot(unit)) }
        }
        return (0..<3).map { side -> Double in
            let (a, b) = (t[side], t[(side + 1) % 3])
            let along = min(1, max(0, (p - a).dot(b - a) / (b - a).dot(b - a)))
            return (p - (a + (b - a) * along)).length
        }.min() ?? .infinity
    }
}

/// The sign from the winding number (implicit spec Errata D18).
extension SignedDistanceMeshTests {
    /// Two cubes of 2 mm, the second 1 mm to the right of the first, as the two shells of a part that was not merged: each is closed, and
    /// they overlap in x from 1 to 2.
    func overlappingCubes() throws -> SignedDistanceMesh {
        let unit = MeshFixtures.cube
        let positions = Self.vectors(unit).map { $0 * 2 } + Self.vectors(unit).map { $0 * 2 + Vector3(1, 0, 0) }
        let indices = unit.triangles + unit.triangles.map { $0 + UInt32(unit.vertexCount) }
        return try SignedDistanceMesh(positions: positions, indices: indices)
    }

    @Test func theRobustSignAgreesWithThePseudonormalOnACleanMesh() throws {
        let cube = try cube()
        for point in [Vector3(0.5, 0.5, 0.5), Vector3(2, 0.5, 0.5), Vector3(0.99, 0.99, 0.5), Vector3(1.01, 1.01, 1.01),
                      Vector3(-1, -1, -1), Vector3(0.2, 0.1, 0.05),
        ] {
            #expect(near(cube.robustSignedDistance(at: point), cube.signedDistance(at: point)), "at \(point)")
            #expect(near(cube.unsignedDistance(at: point), abs(cube.signedDistance(at: point))))
            #expect(cube.isInside(point) == (cube.signedDistance(at: point) < 0))
        }
        #expect(abs(cube.windingNumber(at: Vector3(0.5, 0.5, 0.5)) - 1) < 1e-9)
    }

    @Test func aMeshThatOverlapsItselfStillHasAnInside() throws {
        let mesh = try overlappingCubes()
        // Inside the first cube, 0.1 mm from the second cube's face (x = 1): that face is the nearest feature, and the point is on its
        // outer side. The pseudonormal sign reads outside; this is the misread Check Trapped Volumes must not trust.
        let inFirstOnly = Vector3(0.9, 1, 1)
        #expect(mesh.signedDistance(at: inFirstOnly) > 0, "the pseudonormal sign is fooled here")
        #expect(mesh.isInside(inFirstOnly) && mesh.robustSignedDistance(at: inFirstOnly) < 0)
        #expect(near(mesh.robustSignedDistance(at: inFirstOnly), -0.1))
        #expect(abs(mesh.windingNumber(at: inFirstOnly) - 1) < 1e-9)
        // In both cubes the winding number is 2, and outside both it is 0.
        #expect(abs(mesh.windingNumber(at: Vector3(1.5, 1, 1)) - 2) < 1e-9 && mesh.isInside(Vector3(1.5, 1, 1)))
        #expect(!mesh.isInside(Vector3(4, 1, 1)) && mesh.robustSignedDistance(at: Vector3(4, 1, 1)) > 0)
    }

    @Test func theWindingNumberIsBuiltOnlyWhenAskedFor() throws {
        let cube = try cube()
        _ = cube.signedDistance(at: Vector3(0.5, 0.5, 0.5))
        _ = cube.unsignedDistance(at: Vector3(2, 2, 2))
        #expect(!cube.hasBuiltWindingNumber, "the bake's questions leave the clusters unbuilt")
        #expect(cube.isInside(Vector3(0.5, 0.5, 0.5)) && cube.hasBuiltWindingNumber)
        #expect(!cube.isInside(Vector3(3, 3, 3)), "and a second question reuses them")
    }
}
