// Test fixture file: a small closed mesh for the scene tests.
import CreatorImplicit

enum MeshFixture {
    /// A regular tetrahedron wound counter-clockwise seen from outside.
    static let tetrahedron = TriangleMesh(
        positions: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, -1, -1), SIMD3<Float>(-1, 1, -1), SIMD3<Float>(-1, -1, 1)],
        triangles: [0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 3, 2])
}
