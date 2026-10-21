/// Thin walls (implicit spec §4.6): from each vertex a ray goes inwards, against the normal, and the first surface it meets that faces
/// back at it is the other side of the wall. A vertex whose wall is thinner than `minimum` is flagged, with its faces. Flagged faces
/// that touch, and the two sides of one wall, make one place. A surface that meets the ray edge-on (the next face of a sharp corner) is
/// not the far side of a wall and is passed over, as is any triangle the vertex belongs to.
///
/// A hit closer than `selfHitLimit` on a face that touches the vertex's one-ring (the vertex, its neighbours) is the surface folding back
/// on itself where a sheet closes on a skin, not a wall behind it, and is passed over too: the ray goes on (Errata D18). A knife edge
/// still shows, a little farther along it, where the two sides are a hit's distance apart or more.
/// The accepted limit of the rule: a real wall under `selfHitLimit` whose far face shares a vertex with the one-ring is not told from
/// the fold and is not reported (`aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall` pins it).
public struct ThinWallCheck: Sendable {
    public struct Result: Sendable {
        /// The triangles with a flagged vertex, in order.
        public var triangles: [Int]
        /// How many separate places they make.
        public var places: Int
        /// The thinnest wall found, or `nil` when none is thinner than `minimum`.
        public var thinnest: Double?
    }

    /// A far side must face back against the vertex normal within 60 degrees.
    static let facingLimit = -0.5

    /// A hit nearer than this (millimetres) on a face that touches the start vertex's one-ring is the mesh folding on itself.
    static let selfHitLimit = 0.05

    private let points: [SIMD3<Double>]
    private let corners: [SIMD3<Int32>]
    private let normals: [SIMD3<Double>]
    private let faceNormals: [SIMD3<Double>]
    private let bvh: TriangleBVH
    /// The triangles at vertex `v` are `incident[firstIncident[v]..<firstIncident[v + 1]]`.
    private let firstIncident: [Int32]
    private let incident: [Int32]

    init(_ mesh: TriangleMesh) {
        points = mesh.positions.map { SIMD3<Double>($0) }
        corners = (0..<mesh.triangleCount).map {
            SIMD3(Int32(mesh.triangles[3 * $0]), Int32(mesh.triangles[3 * $0 + 1]), Int32(mesh.triangles[3 * $0 + 2]))
        }
        let points = points
        faceNormals = corners.map { triangle in
            let normal = (points[Int(triangle.y)] - points[Int(triangle.x)]).cross(points[Int(triangle.z)] - points[Int(triangle.x)])
            let length = normal.length
            return length > 0 ? normal / length : .zero
        }
        normals = MeshVertexNormals.of(mesh)
        bvh = TriangleBVH(vertices: points, triangles: corners)
        var counts = [Int32](repeating: 0, count: points.count + 1)
        for triangle in corners {
            for corner in [triangle.x, triangle.y, triangle.z] { counts[Int(corner) + 1] += 1 }
        }
        for index in 1..<counts.count { counts[index] += counts[index - 1] }
        var next = counts
        var listed = [Int32](repeating: 0, count: Int(counts[counts.count - 1]))
        for (index, triangle) in corners.enumerated() {
            for corner in [triangle.x, triangle.y, triangle.z] {
                listed[Int(next[Int(corner)])] = Int32(index)
                next[Int(corner)] += 1
            }
        }
        firstIncident = counts
        incident = listed
    }

    /// `vertex` and the vertices that share a triangle with it.
    private func oneRing(of vertex: Int) -> [Int32] {
        var ring = [Int32(vertex)]
        for slot in Int(firstIncident[vertex])..<Int(firstIncident[vertex + 1]) {
            let triangle = corners[Int(incident[slot])]
            for corner in [triangle.x, triangle.y, triangle.z] where !ring.contains(corner) { ring.append(corner) }
        }
        return ring
    }

    /// How far the wall behind `vertex` is, and the triangle that is its far side, when it is thinner than `limit`.
    func wall(behind vertex: Int, limit: Double) -> (distance: Double, triangle: Int)? {
        var hitTriangle = -1
        // The nearest hit this walk has seen: a leaf can hold a nearer triangle before a farther one, and only the nearer is the wall.
        var nearest = Double.infinity
        let direction = -normals[vertex]
        let ring = oneRing(of: vertex)
        let distance = bvh.nearestHit(origin: points[vertex], direction: direction, limit: limit) { index in
            let triangle = corners[index]
            guard Int(triangle.x) != vertex, Int(triangle.y) != vertex, Int(triangle.z) != vertex,
                  faceNormals[index].dot(normals[vertex]) < Self.facingLimit,
                  let t = Self.hit(points[vertex], direction, points[Int(triangle.x)], points[Int(triangle.y)], points[Int(triangle.z)]),
                  t > 1e-9, t < nearest else { return nil }
            // Close to the vertex, on a face that touches its neighbourhood: the surface folding back, not a wall. The ray goes on.
            if t < Self.selfHitLimit, ring.contains(triangle.x) || ring.contains(triangle.y) || ring.contains(triangle.z) { return nil }
            nearest = t
            hitTriangle = index
            return t
        }
        guard let distance, distance < limit, hitTriangle >= 0 else { return nil }
        return (distance, hitTriangle)
    }

    /// How many vertices go out to the cores together.
    private static let batch = 1 << 16

    /// - Throws: `CancellationError`.
    public static func run(_ mesh: TriangleMesh, minimum: Double) throws -> Result {
        guard mesh.triangleCount > 0, minimum.isFinite, minimum > 0 else { return Result(triangles: [], places: 0, thinnest: nil) }
        let scan = ThinWallCheck(mesh)
        var clusters = VertexClusters(count: scan.points.count)
        var flagged = [Bool](repeating: false, count: scan.points.count)
        var thinnest = Double.infinity
        let vertices = Set(scan.corners.flatMap { [Int($0.x), Int($0.y), Int($0.z)] }).sorted().filter { scan.normals[$0] != .zero }
        // The rays are independent, so batches of them go out side by side; the walls are applied in vertex order.
        for start in stride(from: 0, to: vertices.count, by: Self.batch) {
            try Task.checkCancellation()
            let walls = ParallelMap.map(Array(vertices[start..<min(start + Self.batch, vertices.count)])) { vertex in
                scan.wall(behind: vertex, limit: minimum).map { (vertex: vertex, distance: $0.distance, triangle: $0.triangle) }
            }
            for case let found? in walls {
                flagged[found.vertex] = true
                thinnest = min(thinnest, found.distance)
                // The two sides of a wall are one place.
                clusters.join(found.vertex, Int(scan.corners[found.triangle].x))
            }
        }
        var triangles: [Int] = []
        var anchors: [Int] = []
        for (index, triangle) in scan.corners.enumerated() {
            let marked = [Int(triangle.x), Int(triangle.y), Int(triangle.z)].filter { flagged[$0] }
            guard let first = marked.first else { continue }
            triangles.append(index)
            anchors.append(first)
            for other in marked.dropFirst() { clusters.join(first, other) }
        }
        let places = Set(anchors.map { clusters.root(of: $0) }).count
        return Result(triangles: triangles, places: places, thinnest: triangles.isEmpty ? nil : thinnest)
    }

    /// Möller–Trumbore: the distance along the ray at which it crosses the triangle, or `nil`.
    static func hit(_ origin: SIMD3<Double>, _ direction: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>,
                    _ c: SIMD3<Double>) -> Double? {
        let (edge1, edge2) = (b - a, c - a)
        let pvec = direction.cross(edge2)
        let determinant = edge1.dot(pvec)
        guard abs(determinant) > 1e-14 else { return nil }
        let inverse = 1 / determinant
        let tvec = origin - a
        let u = tvec.dot(pvec) * inverse
        guard u >= 0, u <= 1 else { return nil }
        let qvec = tvec.cross(edge1)
        let v = direction.dot(qvec) * inverse
        guard v >= 0, u + v <= 1 else { return nil }
        return edge2.dot(qvec) * inverse
    }
}
