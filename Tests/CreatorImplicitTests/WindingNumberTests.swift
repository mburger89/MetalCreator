import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The generalized winding number (implicit spec Errata D18): 1 inside a closed mesh and 0 outside, the BVH clusters held to the exact
/// sum, a hollow part and a mesh that overlaps itself.
struct WindingNumberTests {
    /// The winding number machinery over `positions` and `indices`, as `SignedDistanceMesh` builds it.
    func machinery(_ positions: [Vector3], _ indices: [UInt32]) -> WindingNumber {
        let vertices = positions.map { SIMD3($0.x, $0.y, $0.z) }
        let triangles = stride(from: 0, to: indices.count, by: 3).map {
            SIMD3(Int32(indices[$0]), Int32(indices[$0 + 1]), Int32(indices[$0 + 2]))
        }
        return WindingNumber(vertices: vertices, triangles: triangles, bvh: TriangleBVH(vertices: vertices, triangles: triangles))
    }

    func vectors(_ mesh: TriangleMesh) -> [Vector3] { (0..<mesh.vertexCount).map { mesh.point($0) } }

    @Test func aCubeIsOneInsideAndZeroOutside() {
        let cube = machinery(vectors(MeshFixtures.cube), MeshFixtures.cube.triangles)
        func winding(_ x: Double, _ y: Double, _ z: Double) -> Double { cube.value(at: SIMD3(x, y, z), farRatio: .infinity) }
        #expect(abs(winding(0.5, 0.5, 0.5) - 1) < 1e-12)
        #expect(abs(winding(0.99, 0.5, 0.5) - 1) < 1e-12 && abs(winding(0.01, 0.01, 0.01) - 1) < 1e-12)
        #expect(abs(winding(1.01, 0.5, 0.5)) < 1e-12 && abs(winding(-3, 4, 9)) < 1e-12)
        #expect(abs(winding(2, 2, 2)) < 1e-12, "past a corner")
    }

    @Test func theClustersAgreeWithTheExactSumAndClassifyTheSame() {
        let sphere = MeshFixtures.sphere(radius: 5, subdivisions: 4)
        let winding = machinery(sphere.positions, sphere.indices)
        let random = SeededRandom(seed: 11, stream: 2)
        var worst = 0.0
        for index in 0..<400 {
            let point = SIMD3(random.unit(at: 3 * index) * 16 - 8, random.unit(at: 3 * index + 1) * 16 - 8,
                              random.unit(at: 3 * index + 2) * 16 - 8)
            let (fast, exact) = (winding.value(at: point), winding.value(at: point, farRatio: .infinity))
            worst = max(worst, abs(fast - exact))
            #expect(winding.contains(point) == (exact >= 0.5), "at \(point): \(fast) against \(exact)")
        }
        #expect(worst < 0.05, "the far field is within \(worst) of the exact sum")
    }

    @Test func aCavityIsWoundTheOtherWayAndSoIsNotInside() {
        let part = MeshFixtures.hollowCube(size: 10, wall: 1, divisions: 4)
        let winding = machinery(vectors(part), part.triangles)
        #expect(abs(winding.value(at: SIMD3(0.5, 5, 5)) - 1) < 0.05, "in the wall")
        #expect(abs(winding.value(at: SIMD3(5, 5, 5))) < 0.05, "in the cavity")
        #expect(abs(winding.value(at: SIMD3(20, 5, 5))) < 0.05, "outside")
    }

    @Test func anEmptyMeshHasNoWinding() {
        let none = machinery([], [])
        #expect(none.value(at: SIMD3(1, 2, 3)) == 0)
    }
}
