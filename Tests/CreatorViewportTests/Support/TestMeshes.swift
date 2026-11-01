// Test fixture file: hand-built display meshes whose face and edge IDs match FakeKernel's prism numbering.
import CreatorGeometry
import CreatorKernel
import Foundation

enum TestMeshes {
    /// A box mesh numbered like `FakeKernel.extrude` of a rectangle:
    /// - faces 0 bottom, 1 top, 2 front (−Y), 3 right (+X), 4 back (+Y), 5 left (−X)
    /// - edges 2k bottom∩side k, 2k+1 top∩side k, and 8+k side k ∩ side k+1
    /// Triangles are wound outward.
    static func box(_ bounds: BoundingBox) -> DisplayMesh {
        let (x0, y0, z0) = (bounds.min.x, bounds.min.y, bounds.min.z)
        let (x1, y1, z1) = (bounds.max.x, bounds.max.y, bounds.max.z)
        let quads: [(Vector3, [Vector3])] = [
            (Vector3(0, 0, -1), [Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0)]),
            (Vector3(0, 0, 1), [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]),
            (Vector3(0, -1, 0), [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)]),
            (Vector3(1, 0, 0), [Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)]),
            (Vector3(0, 1, 0), [Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1)]),
            (Vector3(-1, 0, 0), [Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1)]),
        ]
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        var triangleFaces: [FaceID] = []
        for (face, quad) in quads.enumerated() {
            let base = UInt32(positions.count)
            positions += quad.1
            normals += Array(repeating: quad.0, count: 4)
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            triangleFaces += [FaceID(face), FaceID(face)]
        }
        // Side k runs from corner k to corner k+1 of the rectangle (front, right, back, left).
        let ring = [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
        var polylines: [EdgeID: [Vector3]] = [:]
        for k in 0..<4 {
            let a = ring[k]
            let b = ring[(k + 1) % 4]
            polylines[EdgeID(2 * k)] = [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0)]
            polylines[EdgeID(2 * k + 1)] = [Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1)]
            polylines[EdgeID(8 + k)] = [Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1)]
        }
        return DisplayMesh(positions: positions, normals: normals, indices: indices, triangleFaces: triangleFaces,
                           edgePolylines: polylines)
    }

    /// A sphere about the origin as one face (ID 0), `segments` of longitude by `segments / 2` of latitude, with exact outward
    /// vertex normals and triangles wound outward.
    static func sphere(radius: Double, segments: Int) -> DisplayMesh {
        let rings = max(segments / 2, 2)
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        for ring in 0...rings {
            let polar = Double.pi * Double(ring) / Double(rings)
            for step in 0...segments {
                let azimuth = 2 * Double.pi * Double(step) / Double(segments)
                let normal = Vector3(sin(polar) * cos(azimuth), sin(polar) * sin(azimuth), cos(polar))
                normals.append(normal)
                positions.append(normal * radius)
            }
        }
        var indices: [UInt32] = []
        let stride = UInt32(segments + 1)
        for ring in 0..<rings {
            for step in 0..<segments {
                let a = UInt32(ring) * stride + UInt32(step)
                let b = a + 1, c = a + stride, d = c + 1
                // Ring 0 is the +Z pole; azimuth runs counter-clockwise seen from +Z, so (a, c, b) faces outward.
                if ring > 0 { indices += [a, c, b] }
                if ring < rings - 1 { indices += [b, c, d] }
            }
        }
        return DisplayMesh(positions: positions, normals: normals, indices: indices,
                           triangleFaces: Array(repeating: FaceID(0), count: indices.count / 3), edgePolylines: [:])
    }
}
