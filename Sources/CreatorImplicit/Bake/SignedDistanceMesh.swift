import Foundation
import CreatorGeometry

/// Why a mesh can't give inside and outside.
public enum MeshDistanceError: Error, Equatable, Sendable {
    /// The mesh has an edge with one face, three or more, or two faces that run the same way (To Implicit's message is
    /// `userMessage`).
    case notClosed

    public var userMessage: String { "This solid isn't closed, so inside and outside are undefined." }
}

/// The signed distance to a closed triangle mesh (implicit spec §4.4): the unsigned distance is the nearest triangle, found by a BVH;
/// the sign comes from the angle-weighted pseudonormal of the nearest feature (Bærentzen and Aanæs, 2005), which is exact for any
/// closed, consistently oriented mesh, with no ray casting and no tolerance. The mesh may be a soup of per-face meshes, as OCCT
/// makes: vertices closer than `weldTolerance` are one vertex first. Negative is inside. Triangles must be counter-clockwise seen from
/// outside, as `Kernel.tessellate` gives them.
public struct SignedDistanceMesh: Sendable {
    private let vertices: [SIMD3<Double>]
    private let triangles: [SIMD3<Int32>]
    private let faceNormals: [SIMD3<Double>]
    /// The angle-weighted normal at each vertex.
    private let vertexNormals: [SIMD3<Double>]
    /// For each triangle, the normal of each of its edges (a, b), (b, c), (c, a): the sum of the two faces' normals.
    private let edgeNormals: [SIMD3<Double>]
    private let bvh: TriangleBVH

    /// The box around the mesh.
    public let bounds: BoundingBox

    /// - Parameters:
    ///   - positions: vertex positions in millimetres.
    ///   - indices: three per triangle.
    ///   - weldTolerance: vertices closer than this (per axis, after rounding to a grid of it) are merged.
    /// - Throws: `MeshDistanceError.notClosed`.
    public init(positions: [Vector3], indices: [UInt32], weldTolerance: Double = 1e-6) throws(MeshDistanceError) {
        let (welded, kept, joined) = Self.weld(positions, indices, tolerance: weldTolerance)
        guard !kept.isEmpty, Self.isClosed(joined) else { throw .notClosed }
        let normals = Self.normals(vertices: welded, triangles: kept)
        self.vertices = welded
        self.triangles = kept
        self.faceNormals = normals.faces
        self.vertexNormals = normals.vertices
        self.edgeNormals = normals.edges
        self.bvh = TriangleBVH(vertices: welded, triangles: kept)
        let low = welded.dropFirst().reduce(welded[0]) { pointwiseMin($0, $1) }
        let high = welded.dropFirst().reduce(welded[0]) { pointwiseMax($0, $1) }
        self.bounds = BoundingBox(min: Vector3(low.x, low.y, low.z), max: Vector3(high.x, high.y, high.z))
    }

    private struct EdgeKey: Hashable {
        var low: Int32
        var high: Int32

        init(_ from: Int32, _ to: Int32) {
            low = min(from, to)
            high = max(from, to)
        }
    }

    /// Merges vertices that round to the same cell of `tolerance` and drops the triangles that merging collapsed or that have no area.
    /// `joined` is the triangles merging left, arealess ones included: a collinear sliver (three distinct points on a line, which a
    /// 3MF's six digits make of a thin triangle) closes the surface it sits in, so it counts for `isClosed`, not for the distance.
    private static func weld(_ positions: [Vector3], _ indices: [UInt32],
                             tolerance: Double) -> (welded: [SIMD3<Double>], kept: [SIMD3<Int32>], joined: [SIMD3<Int32>]) {
        struct Cell: Hashable {
            var x: Int
            var y: Int
            var z: Int
        }
        var merged: [Cell: Int32] = [:]
        var welded: [SIMD3<Double>] = []
        var remap = [Int32](repeating: 0, count: positions.count)
        for (index, position) in positions.enumerated() {
            let cell = Cell(x: Int((position.x / tolerance).rounded()), y: Int((position.y / tolerance).rounded()),
                            z: Int((position.z / tolerance).rounded()))
            if let existing = merged[cell] {
                remap[index] = existing
            } else {
                merged[cell] = Int32(welded.count)
                remap[index] = Int32(welded.count)
                welded.append(SIMD3(position.x, position.y, position.z))
            }
        }
        var kept: [SIMD3<Int32>] = []
        var joined: [SIMD3<Int32>] = []
        for base in stride(from: 0, to: indices.count - 2, by: 3) {
            let triangle = SIMD3(remap[Int(indices[base])], remap[Int(indices[base + 1])], remap[Int(indices[base + 2])])
            guard triangle.x != triangle.y, triangle.y != triangle.z, triangle.z != triangle.x else { continue }
            joined.append(triangle)
            let (a, b, c) = (welded[Int(triangle.x)], welded[Int(triangle.y)], welded[Int(triangle.z)])
            let area = cross(b - a, c - a)
            if (area * area).sum() > 1e-24 { kept.append(triangle) }
        }
        return (welded, kept, joined)
    }

    /// Whether every edge is shared by two faces that run along it in opposite directions.
    private static func isClosed(_ triangles: [SIMD3<Int32>]) -> Bool {
        var faces: [EdgeKey: (count: Int, forward: Int)] = [:]
        for triangle in triangles {
            for side in 0..<3 {
                let (from, to) = (triangle[side], triangle[(side + 1) % 3])
                var entry = faces[EdgeKey(from, to)] ?? (0, 0)
                entry.count += 1
                if from < to { entry.forward += 1 }
                faces[EdgeKey(from, to)] = entry
            }
        }
        return faces.values.allSatisfy { $0.count == 2 && $0.forward == 1 }
    }

    /// The face normals, the angle-weighted vertex normals, and each triangle's three edge normals.
    private static func normals(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>])
        -> (faces: [SIMD3<Double>], vertices: [SIMD3<Double>], edges: [SIMD3<Double>]) {
        var faces: [SIMD3<Double>] = []
        var vertexNormals = [SIMD3<Double>](repeating: .zero, count: vertices.count)
        var edgeSums: [EdgeKey: SIMD3<Double>] = [:]
        for triangle in triangles {
            let corners = [vertices[Int(triangle.x)], vertices[Int(triangle.y)], vertices[Int(triangle.z)]]
            let raw = cross(corners[1] - corners[0], corners[2] - corners[0])
            let normal = raw / (raw * raw).sum().squareRoot()
            faces.append(normal)
            for corner in 0..<3 {
                let (next, previous) = (corners[(corner + 1) % 3] - corners[corner], corners[(corner + 2) % 3] - corners[corner])
                let cosine = (next * previous).sum() / ((next * next).sum() * (previous * previous).sum()).squareRoot()
                vertexNormals[Int(triangle[corner])] += normal * acos(min(1, max(-1, cosine)))
                edgeSums[EdgeKey(triangle[corner], triangle[(corner + 1) % 3]), default: .zero] += normal
            }
        }
        let edges = triangles.flatMap { triangle in
            (0..<3).map { edgeSums[EdgeKey(triangle[$0], triangle[($0 + 1) % 3])] ?? .zero }
        }
        return (faces, vertexNormals, edges)
    }

    /// How many triangles remain after welding and dropping slivers.
    public var triangleCount: Int { triangles.count }

    /// The signed distance from `point` to the surface: negative inside.
    public func signedDistance(at point: Vector3) -> Double {
        let p = SIMD3(point.x, point.y, point.z)
        var best = Double.infinity
        var bestPoint = p
        var bestNormal = SIMD3<Double>.zero
        bvh.search(from: p, bound: { best }, visit: { index in
            let triangle = triangles[index]
            let (a, b, c) = (vertices[Int(triangle.x)], vertices[Int(triangle.y)], vertices[Int(triangle.z)])
            let (closest, feature) = Self.closestPoint(on: (a, b, c), to: p)
            let offset = p - closest
            let squared = (offset * offset).sum()
            guard squared < best else { return }
            best = squared
            bestPoint = closest
            switch feature {
            case .face: bestNormal = faceNormals[index]
            case .vertex(let corner): bestNormal = vertexNormals[Int(triangle[corner])]
            case .edge(let side): bestNormal = edgeNormals[3 * index + side]
            }
        })
        guard best.isFinite else { return .infinity }
        let distance = best.squareRoot()
        let side = ((p - bestPoint) * bestNormal).sum()
        return side < 0 ? -distance : distance
    }

    // MARK: Closest point on a triangle

    private enum Feature {
        case face
        case vertex(Int)
        case edge(Int)
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    /// The nearest point of triangle `abc` to `p` and the feature it lies on (Ericson, Real-Time Collision Detection, 5.1.5).
    private static func closestPoint(on triangle: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>),
                                     to p: SIMD3<Double>) -> (SIMD3<Double>, Feature) {
        let (a, b, c) = triangle
        let (ab, ac, ap) = (b - a, c - a, p - a)
        let d1 = (ab * ap).sum(), d2 = (ac * ap).sum()
        if d1 <= 0, d2 <= 0 { return (a, .vertex(0)) }
        let bp = p - b
        let d3 = (ab * bp).sum(), d4 = (ac * bp).sum()
        if d3 >= 0, d4 <= d3 { return (b, .vertex(1)) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 { return (a + ab * (d1 / (d1 - d3)), .edge(0)) }
        let cp = p - c
        let d5 = (ab * cp).sum(), d6 = (ac * cp).sum()
        if d6 >= 0, d5 <= d6 { return (c, .vertex(2)) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 { return (a + ac * (d2 / (d2 - d6)), .edge(2)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 {
            return (b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))), .edge(1))
        }
        let denominator = 1 / (va + vb + vc)
        return (a + ab * (vb * denominator) + ac * (vc * denominator), .face)
    }
}
