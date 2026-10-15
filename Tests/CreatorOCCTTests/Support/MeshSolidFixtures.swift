// Test fixture file: closed triangle meshes for Mesh to Solid on OCCT. CreatorOCCTTests cannot see CreatorImplicit.
import CreatorGeometry

enum MeshSolidFixtures {
    struct Mesh {
        var positions: [SIMD3<Float>]
        var triangles: [UInt32]
    }

    /// A cube from `corner` of the given `size`, twelve triangles, counter-clockwise seen from outside (or from inside when `inside`).
    static func cube(size: Float, at corner: SIMD3<Float> = .zero, inside: Bool = false) -> Mesh {
        let positions = (0..<8).map { bit in
            corner + size * SIMD3<Float>(bit & 1 == 0 ? 0 : 1, bit & 2 == 0 ? 0 : 1, bit & 4 == 0 ? 0 : 1)
        }
        // Vertex numbers are bits (x, y, z); each face is two triangles.
        let outward: [UInt32] = [0, 2, 3, 0, 3, 1, 4, 5, 7, 4, 7, 6, 0, 1, 5, 0, 5, 4, 2, 6, 7, 2, 7, 3, 0, 4, 6, 0, 6, 2, 1, 3, 7, 1, 7, 5]
        var triangles = outward
        if inside {
            for base in stride(from: 0, to: triangles.count, by: 3) { triangles.swapAt(base + 1, base + 2) }
        }
        return Mesh(positions: positions, triangles: triangles)
    }

    /// A sphere of `radius` from an octahedron split `subdivisions` times; 8 × 4^n triangles.
    static func sphere(radius: Double, subdivisions: Int) -> Mesh {
        var points = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
        var faces: [[Int]] = [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]
        for _ in 0..<subdivisions {
            var middles: [[Int]: Int] = [:]
            func middle(_ a: Int, _ b: Int) -> Int {
                let key = [min(a, b), max(a, b)]
                if let known = middles[key] { return known }
                points.append(((points[a] + points[b]) * 0.5).normalized ?? .unitX)
                middles[key] = points.count - 1
                return points.count - 1
            }
            faces = faces.flatMap { face -> [[Int]] in
                let (a, b, c) = (face[0], face[1], face[2])
                let (ab, bc, ca) = (middle(a, b), middle(b, c), middle(c, a))
                return [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]
            }
        }
        let positions = points.map { SIMD3(Float($0.x * radius), Float($0.y * radius), Float($0.z * radius)) }
        return Mesh(positions: positions, triangles: faces.flatMap { $0.map { UInt32($0) } })
    }

    /// The enclosed volume of a mesh in cubic millimetres.
    static func volume(_ mesh: Mesh) -> Double {
        func point(_ index: UInt32) -> Vector3 {
            let p = mesh.positions[Int(index)]
            return Vector3(Double(p.x), Double(p.y), Double(p.z))
        }
        var sum = 0.0
        for base in stride(from: 0, to: mesh.triangles.count, by: 3) {
            sum += point(mesh.triangles[base]).dot(point(mesh.triangles[base + 1]).cross(point(mesh.triangles[base + 2])))
        }
        return sum / 6
    }

    /// `first` and `second` as one mesh.
    static func joined(_ first: Mesh, _ second: Mesh) -> Mesh {
        Mesh(positions: first.positions + second.positions,
             triangles: first.triangles + second.triangles.map { $0 + UInt32(first.positions.count) })
    }
}
