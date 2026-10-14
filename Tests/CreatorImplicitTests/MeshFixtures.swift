import CreatorImplicit

/// Small closed meshes for the mesh tests.
enum MeshFixtures {
    /// A regular tetrahedron wound counter-clockwise seen from outside.
    static let tetrahedron = TriangleMesh(
        positions: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, -1, -1), SIMD3<Float>(-1, 1, -1), SIMD3<Float>(-1, -1, 1)],
        triangles: [0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 3, 2])

    /// A unit cube from (0, 0, 0) to (1, 1, 1), twelve triangles.
    static let cube = TriangleMesh(
        positions: [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 1, 0), SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 1, 1), SIMD3<Float>(0, 1, 1),
        ],
        triangles: [
            0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7,
        ])
}
