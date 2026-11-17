import CreatorGraph

/// The triangles an evaluation has made, in world space, and the budgets it keeps: triangles, visited nodes and depth.
final class VRMLScene {
    static let maximumVisits = 5_000_000

    private(set) var corners: [SIMD3<Float>] = []
    var skippedGeometry = false
    /// Whether the file names other files (`Inline`) that are not read.
    var referencesFiles = false
    /// The format named in this scene's refusals.
    let format: String
    private let triangleLimit: Int
    private let isCancelled: () -> Bool
    private var visits = 0
    private var work = 0
    private var ticks = 0
    /// The most points, indices and corners an evaluation handles: well above what the triangle limit allows, yet finite, so a
    /// `USE` that doubles a huge face set stops.
    private let workLimit: Int

    init(triangleLimit: Int, format: String = "VRML", isCancelled: @escaping () -> Bool) {
        self.format = format
        self.triangleLimit = triangleLimit
        workLimit = 4 * triangleLimit + 64_000_000
        self.isCancelled = isCancelled
    }

    /// Counts one visit to a node `depth` levels down. A `USE` shares a node, so the same node can be visited many times: the budget
    /// stops a file that doubles itself at each level.
    func visit(depth: Int) throws {
        guard depth <= VRMLParser.maximumDepth else { throw VRMLReader.sceneProblem(format, "nests too deeply.") }
        visits += 1
        guard visits <= Self.maximumVisits else { throw VRMLReader.sceneProblem(format, "is too complex.") }
        try pulse()
    }

    /// One unit of per-point or per-index work, counted against its own budget and asking about cancellation.
    func tick() throws {
        work += 1
        guard work <= workLimit else { throw VRMLReader.sceneProblem(format, "is too complex.") }
        try pulse()
    }

    private func pulse() throws {
        ticks += 1
        if ticks % 65_536 == 0, isCancelled() { throw CancellationError() }
    }

    func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) throws {
        guard corners.count / 3 < triangleLimit else { throw MeshImportProblem.overTriangleLimit }
        guard [a, b, c].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw MeshImportProblem.coordinatesOverflow
        }
        corners.append(a)
        corners.append(b)
        corners.append(c)
    }

    /// A box centred on the origin, 12 triangles wound counter-clockwise seen from outside.
    func addBox(size: SIMD3<Double>, matrix: VRMLMatrix, reversed: Bool) throws {
        let h = size / 2
        let p = (0..<8).map { corner -> SIMD3<Float> in
            let local = SIMD3(corner & 1 == 0 ? -h.x : h.x, corner & 2 == 0 ? -h.y : h.y, corner & 4 == 0 ? -h.z : h.z)
            return SIMD3<Float>(matrix.apply(local))
        }
        let quads = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
        let flip = reversed != (matrix.determinant < 0)
        for quad in quads {
            let (a, b, c, d) = (p[quad[0]], p[quad[1]], p[quad[2]], p[quad[3]])
            if flip {
                try addTriangle(a, c, b)
                try addTriangle(a, d, c)
            } else {
                try addTriangle(a, b, c)
                try addTriangle(a, c, d)
            }
        }
    }

    /// An `IndexedTriangleSet`: every three indices are a triangle; a remainder of one or two is ignored.
    func addTriangles(points: [Float], indices: [Float], matrix: VRMLMatrix, counterClockwise: Bool) throws {
        let world = try worldPoints(points, matrix)
        let flip = counterClockwise == (matrix.determinant < 0)
        for start in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            try tick()
            var corner: [SIMD3<Float>] = []
            for value in indices[start..<(start + 3)] {
                guard value >= 0, value < Float(world.count), value == value.rounded() else {
                    throw VRMLReader.sceneProblem(format, "has a face that names a point it doesn't have.")
                }
                corner.append(world[Int(value)])
            }
            if flip { try addTriangle(corner[0], corner[2], corner[1]) } else { try addTriangle(corner[0], corner[1], corner[2]) }
        }
    }

    private func worldPoints(_ points: [Float], _ matrix: VRMLMatrix) throws -> [SIMD3<Float>] {
        let count = points.count / 3
        var world: [SIMD3<Float>] = []
        world.reserveCapacity(count)
        for index in 0..<count {
            try tick()
            world.append(SIMD3<Float>(matrix.apply(SIMD3(Double(points[3 * index]), Double(points[3 * index + 1]),
                                                         Double(points[3 * index + 2])))))
        }
        return world
    }

    /// An `IndexedFaceSet`: `indices` are faces of point indices ended by -1, fanned from their first point.
    func addFaces(points: [Float], indices: [Float], matrix: VRMLMatrix, counterClockwise: Bool) throws {
        let world = try worldPoints(points, matrix)
        let count = world.count
        let flip = counterClockwise == (matrix.determinant < 0)
        var face: [Int] = []
        for value in indices {
            try tick()
            if value == -1 {
                try fan(face, world, reversed: flip)
                face.removeAll(keepingCapacity: true)
                continue
            }
            guard value >= 0, value < Float(count), value == value.rounded() else {
                throw VRMLReader.sceneProblem(format, "has a face that names a point it doesn't have.")
            }
            face.append(Int(value))
        }
        try fan(face, world, reversed: flip)
    }

    private func fan(_ face: [Int], _ world: [SIMD3<Float>], reversed: Bool) throws {
        guard face.count >= 3 else { return }
        for offset in 1..<(face.count - 1) {
            let (a, b, c) = (world[face[0]], world[face[offset]], world[face[offset + 1]])
            try tick()
            if reversed { try addTriangle(a, c, b) } else { try addTriangle(a, b, c) }
        }
    }
}
