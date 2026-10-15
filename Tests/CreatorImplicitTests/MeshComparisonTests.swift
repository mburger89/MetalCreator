import Testing
@testable import CreatorImplicit

/// The yardstick of the GPU agreement suite, tried on meshes whose difference is known.
struct MeshComparisonTests {
    static let cube = MeshFixtures.cube

    @Test func aMeshAgreesWithItself() {
        let comparison = MeshComparison(reference: Self.cube, candidate: Self.cube)
        #expect(comparison.farthest == 0 && comparison.unmatched == 0)
    }

    @Test func aSlideAlongTheSurfaceIsCountedInFarthestAndNotAlongTheNormal() {
        let normals = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 8)
        let reference = TriangleMesh(positions: Self.cube.positions, normals: normals, triangles: Self.cube.triangles)
        var slid = reference
        slid.positions = slid.positions.map { $0 + SIMD3(0.001, 0, 0) }
        let slide = MeshComparison(reference: reference, candidate: slid)
        #expect(abs(slide.farthest - 0.001) < 1e-6 && slide.farthestAlongNormal < 1e-6 && slide.unmatched == 0)
        var raised = reference
        raised.positions = raised.positions.map { $0 + SIMD3(0, 0, 0.002) }
        let rise = MeshComparison(reference: reference, candidate: raised)
        #expect(abs(rise.farthest - 0.002) < 1e-6 && abs(rise.farthestAlongNormal - 0.002) < 1e-6)
    }

    @Test func aNormalTurnedAroundOrTippedIsCountedInSmallestNormalDot() {
        let up = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 8)
        let reference = TriangleMesh(positions: Self.cube.positions, normals: up, triangles: Self.cube.triangles)
        func comparison(_ normal: SIMD3<Float>?) -> MeshComparison {
            var candidate = reference
            if let normal { candidate.normals[3] = normal }
            return MeshComparison(reference: reference, candidate: candidate)
        }
        #expect(comparison(nil).smallestNormalDot == 1)
        #expect(comparison(SIMD3(0, 0, -1)).smallestNormalDot == -1)
        #expect(abs(comparison(SIMD3(0, 0.6, 0.8)).smallestNormalDot - 0.8) < 1e-6)
        // Vertices without normals (a mesh made without the snap) are not counted.
        var bare = reference
        bare.normals = [SIMD3<Float>](repeating: .zero, count: 8)
        #expect(MeshComparison(reference: reference, candidate: bare).smallestNormalDot == 1)
    }

    @Test func aVertexWithNoMatchIsCountedFromEitherSide() {
        var extra = Self.cube
        extra.positions.append(SIMD3(5, 5, 5))
        extra.normals = []
        let comparison = MeshComparison(reference: Self.cube, candidate: extra)
        #expect(comparison.unmatched == 1)
        #expect(MeshComparison(reference: extra, candidate: Self.cube).unmatched == 1)
    }
}
