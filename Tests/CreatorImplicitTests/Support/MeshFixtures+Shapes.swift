import CreatorGeometry
import CreatorImplicit

extension MeshFixtures {
    /// A cube from (0, 0, 0) to (1, 1, 1) with `divisions` squares along each edge of each face, two triangles to a square, wound
    /// counter-clockwise seen from outside, with vertices shared between faces.
    static func subdividedCube(divisions n: Int) -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        var numbers: [[Int]: UInt32] = [:]
        var triangles: [UInt32] = []
        func vertex(_ p: Vector3) -> UInt32 {
            let key = [Int((p.x * Double(n)).rounded()), Int((p.y * Double(n)).rounded()), Int((p.z * Double(n)).rounded())]
            if let known = numbers[key] { return known }
            positions.append(SIMD3(Float(p.x), Float(p.y), Float(p.z)))
            numbers[key] = UInt32(positions.count - 1)
            return UInt32(positions.count - 1)
        }
        // Each face: its origin and the two directions u and v, with u × v pointing out of the cube.
        let faces: [(origin: Vector3, u: Vector3, v: Vector3)] = [
            (Vector3(1, 0, 0), .unitY, .unitZ), (Vector3(0, 0, 0), .unitZ, .unitY),
            (Vector3(0, 1, 0), .unitZ, .unitX), (Vector3(0, 0, 0), .unitX, .unitZ),
            (Vector3(0, 0, 1), .unitX, .unitY), (Vector3(0, 0, 0), .unitY, .unitX),
        ]
        for face in faces {
            for i in 0..<n {
                for j in 0..<n {
                    func corner(_ di: Int, _ dj: Int) -> UInt32 {
                        vertex(face.origin + face.u * (Double(i + di) / Double(n)) + face.v * (Double(j + dj) / Double(n)))
                    }
                    let (p00, p10, p11, p01) = (corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 1))
                    triangles += [p00, p10, p11, p00, p11, p01]
                }
            }
        }
        return TriangleMesh(positions: positions, triangles: triangles)
    }

    /// A flat square patch in the XY plane, `divisions` squares along each side, 10 mm wide, facing +Z. It is open: its border has
    /// edges with one face.
    static func patch(divisions n: Int) -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        for j in 0...n {
            for i in 0...n { positions.append(SIMD3(Float(i) * 10 / Float(n), Float(j) * 10 / Float(n), 0)) }
        }
        var triangles: [UInt32] = []
        for j in 0..<n {
            for i in 0..<n {
                let (a, b) = (UInt32(j * (n + 1) + i), UInt32(j * (n + 1) + i + 1))
                let (c, d) = (a + UInt32(n + 1), b + UInt32(n + 1))
                triangles += [a, b, d, a, d, c]
            }
        }
        return TriangleMesh(positions: positions, triangles: triangles)
    }

    /// A sphere of `radius` as a `TriangleMesh`.
    static func sphereMesh(radius: Double, subdivisions: Int) -> TriangleMesh {
        let shape = sphere(radius: radius, subdivisions: subdivisions)
        return TriangleMesh(positions: shape.positions.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }, triangles: shape.indices)
    }
}
