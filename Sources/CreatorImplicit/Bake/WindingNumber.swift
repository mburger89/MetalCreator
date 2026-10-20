import Foundation

/// The generalized winding number of a closed triangle mesh (Jacobson, Kavan and Sorkine-Hornung, 2013): the sum of the solid angles
/// the triangles subtend at a point, over 4π. It is 1 inside a closed, consistently wound mesh, 0 outside, and it degrades smoothly where
/// the mesh overlaps itself or folds, which is where a sign taken from the nearest feature's normal flips.
///
/// A mesh with hundreds of thousands of triangles is not summed triangle by triangle. Each node of the BVH holds the vector area and the
/// area-weighted centroid of its triangles, and a node whose box is far from the point (`farRatio` times its radius) counts as one
/// dipole (Barill et al., 2018, the zeroth order): the far part of the sum costs one term per node, and only the triangles near the point
/// are summed exactly. The error of a far node is about (radius ÷ distance)³ of its own solid angle, so the value is within a few
/// hundredths of the exact one; `contains(_:)` sums exactly when the value is within `margin` of ½, so a point is never classified
/// on the far field's error.
struct WindingNumber: Sendable {
    /// A node's far field: the vector area `Σ ½ (b − a) × (c − a)`, the area-weighted centre, the total area and the radius from the
    /// centre to the farthest vertex.
    private struct Cluster: Sendable {
        var centre: SIMD3<Double>
        var vectorArea: SIMD3<Double>
        var area: Double
        var radius: Double
    }

    /// A node is a dipole when the point is farther than this many radii from its centre.
    static let farRatio = 3.0

    /// How near ½ the far field's value may be before `contains(_:)` sums exactly.
    static let margin = 0.15

    private let vertices: [SIMD3<Double>]
    private let triangles: [SIMD3<Int32>]
    private let bvh: TriangleBVH
    private let clusters: [Cluster]

    /// `bvh` must have been built over the same `vertices` and `triangles`.
    init(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>], bvh: TriangleBVH) {
        self.vertices = vertices
        self.triangles = triangles
        self.bvh = bvh
        var clusters = [Cluster](repeating: Cluster(centre: .zero, vectorArea: .zero, area: 0, radius: 0), count: bvh.nodes.count)
        // A node's children come after it, so walking backwards finishes the children first.
        for index in bvh.nodes.indices.reversed() {
            let node = bvh.nodes[index]
            if node.count > 0 {
                clusters[index] = Self.leaf(slots: Int(node.first)..<Int(node.first + node.count), bvh: bvh, vertices: vertices,
                                            triangles: triangles)
            } else {
                clusters[index] = Self.join(clusters[Int(node.first)], clusters[Int(node.second)])
            }
        }
        self.clusters = clusters
    }

    private static func leaf(slots: Range<Int>, bvh: TriangleBVH, vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>]) -> Cluster {
        var vectorArea = SIMD3<Double>.zero, weighted = SIMD3<Double>.zero, area = 0.0, plain = SIMD3<Double>.zero
        for slot in slots {
            let (a, b, c) = corners(Int(bvh.order[slot]), vertices, triangles)
            let normal = cross(b - a, c - a) * 0.5
            let size = (normal * normal).sum().squareRoot()
            let centroid = (a + b + c) / 3
            vectorArea += normal
            weighted += centroid * size
            plain += centroid
            area += size
        }
        let centre = area > 0 ? weighted / area : plain / Double(max(slots.count, 1))
        var radius = 0.0
        for slot in slots {
            let (a, b, c) = corners(Int(bvh.order[slot]), vertices, triangles)
            for corner in [a, b, c] { radius = max(radius, length(corner - centre)) }
        }
        return Cluster(centre: centre, vectorArea: vectorArea, area: area, radius: radius)
    }

    private static func join(_ left: Cluster, _ right: Cluster) -> Cluster {
        let area = left.area + right.area
        let centre = area > 0 ? (left.centre * left.area + right.centre * right.area) / area : (left.centre + right.centre) / 2
        let radius = max(length(left.centre - centre) + left.radius, length(right.centre - centre) + right.radius)
        return Cluster(centre: centre, vectorArea: left.vectorArea + right.vectorArea, area: area, radius: radius)
    }

    private static func corners(_ index: Int, _ vertices: [SIMD3<Double>],
                                _ triangles: [SIMD3<Int32>]) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        let triangle = triangles[index]
        return (vertices[Int(triangle.x)], vertices[Int(triangle.y)], vertices[Int(triangle.z)])
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func length(_ a: SIMD3<Double>) -> Double { (a * a).sum().squareRoot() }

    /// The signed solid angle of triangle `abc` seen from the origin (Van Oosterom and Strackee, 1983).
    private static func solidAngle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double {
        let (la, lb, lc) = (length(a), length(b), length(c))
        let numerator = (a * cross(b, c)).sum()
        let denominator = la * lb * lc + (a * b).sum() * lc + (a * c).sum() * lb + (b * c).sum() * la
        return 2 * atan2(numerator, denominator)
    }

    /// The winding number at `point`: about 1 inside a closed mesh and 0 outside. `farRatio` is how far a node must be to count as a
    /// dipole; `.infinity` sums every triangle exactly.
    func value(at point: SIMD3<Double>, farRatio: Double = Self.farRatio) -> Double {
        guard !bvh.nodes.isEmpty else { return 0 }
        var total = 0.0
        var stack = [0]
        stack.reserveCapacity(64)
        while let index = stack.popLast() {
            let cluster = clusters[index]
            let offset = cluster.centre - point
            let squared = (offset * offset).sum()
            let reach = farRatio * cluster.radius
            if squared > reach * reach {
                total += (cluster.vectorArea * offset).sum() / (squared * squared.squareRoot())
                continue
            }
            let node = bvh.nodes[index]
            if node.count > 0 {
                for slot in Int(node.first)..<Int(node.first + node.count) {
                    let (a, b, c) = Self.corners(Int(bvh.order[slot]), vertices, triangles)
                    total += Self.solidAngle(a - point, b - point, c - point)
                }
            } else {
                stack.append(Int(node.first))
                stack.append(Int(node.second))
            }
        }
        return total / (4 * Double.pi)
    }

    /// Whether `point` is inside: the winding number is at least ½. The far field decides unless it is near ½.
    func contains(_ point: SIMD3<Double>) -> Bool {
        let fast = value(at: point)
        if abs(fast - 0.5) > Self.margin { return fast >= 0.5 }
        return value(at: point, farRatio: .infinity) >= 0.5
    }
}
