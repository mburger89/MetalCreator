import CreatorGeometry
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

extension MeshFixtures {
    /// A sphere of `radius` about the origin, made by splitting the faces of an octahedron `subdivisions` times and pushing the
    /// vertices out to the sphere. Wound counter-clockwise seen from outside.
    static func sphere(radius: Double, subdivisions: Int) -> (positions: [Vector3], indices: [UInt32]) {
        var positions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
        var triangles: [[Int]] = [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
        for _ in 0..<subdivisions {
            var midpoints: [[Int]: Int] = [:]
            func middle(_ a: Int, _ b: Int) -> Int {
                let key = [min(a, b), max(a, b)]
                if let existing = midpoints[key] { return existing }
                positions.append(((positions[a] + positions[b]) * 0.5).normalized ?? .unitX)
                midpoints[key] = positions.count - 1
                return positions.count - 1
            }
            triangles = triangles.flatMap { triangle -> [[Int]] in
                let (a, b, c) = (triangle[0], triangle[1], triangle[2])
                let (ab, bc, ca) = (middle(a, b), middle(b, c), middle(c, a))
                return [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]
            }
        }
        return (positions.map { $0 * radius }, triangles.flatMap { $0.map { UInt32($0) } })
    }

    /// The cube mesh with its vertices doubled per face, as OCCT makes them: every triangle has three vertices of its own.
    static var cubeSoup: (positions: [Vector3], indices: [UInt32]) {
        let cube = MeshFixtures.cube
        let positions = cube.triangles.map { index -> Vector3 in
            let p = cube.positions[Int(index)]
            return Vector3(Double(p.x), Double(p.y), Double(p.z))
        }
        return (positions, (0..<UInt32(positions.count)).map { $0 })
    }
}
