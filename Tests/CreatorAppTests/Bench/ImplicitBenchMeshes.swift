// Test fixture file: the big meshes of ImplicitBench rows i-5 and i-6, checked in the default run at small sizes.
import CreatorGeometry
import Foundation

/// Closed triangle meshes of an exact, large size for the mesh-tool benchmarks.
enum ImplicitBenchMeshes {
    struct Mesh {
        var positions: [SIMD3<Float>]
        var triangles: [UInt32]

        var triangleCount: Int { triangles.count / 3 }
    }

    /// A sphere from an octahedron split `subdivisions` times: 8 × 4^n triangles (2,097,152 at 9), wound counter-clockwise seen
    /// from outside.
    static func sphere(subdivisions: Int, radius: Double = 50) -> Mesh {
        var points: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
        var faces: [UInt32] = [0, 2, 4, 2, 1, 4, 1, 3, 4, 3, 0, 4, 2, 0, 5, 1, 2, 5, 3, 1, 5, 0, 3, 5]
        for _ in 0..<subdivisions {
            var middles: [UInt64: UInt32] = [:]
            middles.reserveCapacity(faces.count / 2)
            func middle(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if let known = middles[key] { return known }
                let sum = points[Int(a)] + points[Int(b)]
                points.append(sum / (sum * sum).sum().squareRoot())
                middles[key] = UInt32(points.count - 1)
                return UInt32(points.count - 1)
            }
            var next: [UInt32] = []
            next.reserveCapacity(faces.count * 4)
            for base in stride(from: 0, to: faces.count, by: 3) {
                let (a, b, c) = (faces[base], faces[base + 1], faces[base + 2])
                let (ab, bc, ca) = (middle(a, b), middle(b, c), middle(c, a))
                next += [a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]
            }
            faces = next
        }
        return Mesh(positions: points.map { $0 * Float(radius) }, triangles: faces)
    }

    /// A latitude and longitude sphere with exactly 2 × segments × (rings − 1) triangles (100,000 for 400 and 126), the poles fans.
    static func uvSphere(segments: Int, rings: Int, radius: Double = 40) -> Mesh {
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, Float(radius))]
        for ring in 1..<rings {
            let polar = Double.pi * Double(ring) / Double(rings)
            for segment in 0..<segments {
                let azimuth = 2 * Double.pi * Double(segment) / Double(segments)
                positions.append(SIMD3(Float(radius * sin(polar) * cos(azimuth)), Float(radius * sin(polar) * sin(azimuth)),
                                       Float(radius * cos(polar))))
            }
        }
        positions.append(SIMD3(0, 0, -Float(radius)))
        let south = UInt32(positions.count - 1)
        func vertex(_ ring: Int, _ segment: Int) -> UInt32 { UInt32(1 + (ring - 1) * segments + segment % segments) }
        var triangles: [UInt32] = []
        for segment in 0..<segments {
            triangles += [0, vertex(1, segment), vertex(1, segment + 1)]
        }
        for ring in 1..<(rings - 1) {
            for segment in 0..<segments {
                let (a, b) = (vertex(ring, segment), vertex(ring, segment + 1))
                let (c, d) = (vertex(ring + 1, segment), vertex(ring + 1, segment + 1))
                triangles += [a, c, d, a, d, b]
            }
        }
        for segment in 0..<segments {
            triangles += [south, vertex(rings - 1, segment + 1), vertex(rings - 1, segment)]
        }
        return Mesh(positions: positions, triangles: triangles)
    }
}
