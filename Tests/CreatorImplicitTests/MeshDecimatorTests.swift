import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Decimation (implicit spec §4.5, §7): fewer triangles, the surface within the tolerance, still a closed manifold.
struct MeshDecimatorTests {
    func decimated(_ mesh: TriangleMesh, tolerance: Double) throws -> TriangleMesh {
        let output = try MeshDecimator.decimate(positions: mesh.positions, triangles: mesh.triangles, tolerance: tolerance)
        return TriangleMesh(positions: output.positions, triangles: output.triangles)
    }

    @Test func aSubdividedCubeCollapsesToItsCornersAndFaces() throws {
        let cube = MeshFixtures.subdividedCube(divisions: 6)
        #expect(cube.triangleCount == 432 && MeshTopology(cube).isClosedManifold)
        let result = try decimated(cube, tolerance: 0.001)
        let topology = MeshTopology(result)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        #expect(result.triangleCount <= 24, "a cube needs 12 triangles; got \(result.triangleCount)")
        #expect(abs(result.signedVolume - 1) < 1e-9 && abs(result.surfaceArea - 6) < 1e-9)
        #expect(MeshDistance.hausdorff(cube, result) < 1e-6)
        let corners = Set(result.positions.filter { $0.x.rounded() == $0.x && $0.y.rounded() == $0.y && $0.z.rounded() == $0.z })
        #expect(corners.count == 8, "all eight corners survive")
    }

    @Test func aSphereLosesTrianglesAndStaysWithinTheTolerance() throws {
        let sphere = MeshFixtures.sphereMesh(radius: 10, subdivisions: 3)
        let tolerance = 0.3
        let result = try decimated(sphere, tolerance: tolerance)
        let topology = MeshTopology(result)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        #expect(result.triangleCount < sphere.triangleCount * 9 / 10, "\(sphere.triangleCount) → \(result.triangleCount)")
        let distance = MeshDistance.hausdorff(sphere, result)
        #expect(distance <= tolerance, "Hausdorff \(distance) against a tolerance of \(tolerance)")
        #expect(result.signedVolume > 0)
    }

    @Test func aLargerToleranceKeepsFewerTriangles() throws {
        let sphere = MeshFixtures.sphereMesh(radius: 10, subdivisions: 3)
        let tight = try decimated(sphere, tolerance: 0.3)
        let loose = try decimated(sphere, tolerance: 1)
        #expect(loose.triangleCount < tight.triangleCount && tight.triangleCount < sphere.triangleCount)
        #expect(MeshDistance.hausdorff(sphere, loose) <= 1 && MeshDistance.hausdorff(sphere, tight) <= 0.3)
    }

    @Test func aToleranceOfZeroLeavesACurvedSurfaceAlone() throws {
        let sphere = MeshFixtures.sphereMesh(radius: 10, subdivisions: 3)
        let result = try decimated(sphere, tolerance: 0)
        #expect(result.triangleCount == sphere.triangleCount)
    }

    @Test func aTetrahedronIsTheSmallestMeshLeft() throws {
        let result = try decimated(MeshFixtures.tetrahedron, tolerance: 100)
        #expect(result.triangleCount == 4 && MeshTopology(result).isClosedManifold)
        let blob = try decimated(MeshFixtures.sphereMesh(radius: 1, subdivisions: 3), tolerance: 100)
        #expect(blob.triangleCount >= 4 && MeshTopology(blob).isClosedManifold)
    }

    @Test func anOpenPatchKeepsItsEdgeExactly() throws {
        let patch = MeshFixtures.patch(divisions: 10)
        let output = try MeshDecimator.decimate(positions: patch.positions, triangles: patch.triangles, tolerance: 0.001)
        #expect(output.triangles.count < patch.triangles.count / 3, "the flat inside collapses")
        let border = { (p: SIMD3<Float>) in p.x == 0 || p.x == 10 || p.y == 0 || p.y == 10 }
        let before = Set(patch.positions.filter(border))
        let after = Set(output.positions.filter(border))
        #expect(before.count == 40 && before == after, "every border vertex is where it was")
        let result = TriangleMesh(positions: output.positions, triangles: output.triangles)
        let topology = MeshTopology(result)
        #expect(topology.overfullEdgeCount == 0 && topology.inconsistentEdgeCount == 0 && topology.degenerateTriangleCount == 0)
        #expect(topology.openEdgeCount == 40, "the border has the same 40 edges")
        #expect(abs(result.surfaceArea - 100) < 1e-4)
    }

    @Test func eachOutputVertexNamesTheInputVertexItCameFrom() throws {
        let patch = MeshFixtures.patch(divisions: 6)
        let output = try MeshDecimator.decimate(positions: patch.positions, triangles: patch.triangles, tolerance: 0.001)
        #expect(output.origin.count == output.positions.count)
        let border = { (p: SIMD3<Float>) in p.x == 0 || p.x == 10 || p.y == 0 || p.y == 10 }
        for (index, origin) in output.origin.enumerated() where border(output.positions[index]) {
            #expect(patch.positions[Int(origin)] == output.positions[index])
        }
    }

    @Test func threeFacesOnOneEdgeCannotBeSimplified() {
        let positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1)]
        let fin: [UInt32] = [0, 1, 2, 0, 3, 1, 0, 1, 4]
        #expect(throws: MeshDecimator.Failure.nonManifold(edges: 1)) {
            try MeshDecimator.decimate(positions: positions, triangles: fin, tolerance: 1)
        }
        #expect(MeshDecimator.Failure.nonManifold(edges: 1).userMessage.contains("more than two faces"))
    }

    @Test func triangleListsWithBadIndicesAreIgnoredNotTrusted() throws {
        let output = try MeshDecimator.decimate(positions: MeshFixtures.tetrahedron.positions,
                                                triangles: MeshFixtures.tetrahedron.triangles + [0, 0, 1, 0, 1, 99, 7], tolerance: 0)
        #expect(output.triangles.count == 12)
    }
}
