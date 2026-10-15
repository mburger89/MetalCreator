import CreatorGeometry
@testable import CreatorImplicit

/// How far apart two meshes' vertices are, matched by nearness: every vertex of each mesh against the nearest of the other's. Two
/// meshes of one lattice have one vertex per crossed edge, so the nearest vertex is the same edge's, unless the surface is within a
/// voxel of itself, which the fixtures keep clear of.
struct MeshComparison {
    /// The largest distance from a vertex of either mesh to the nearest of the other's.
    var farthest: Float = 0
    /// The largest distance, taken along the reference's normal at the matched vertex, from a candidate vertex to its match: the
    /// distance between the two *surfaces*, where `farthest` also counts a slide along the surface. Zero when the reference has no normals.
    var farthestAlongNormal: Float = 0
    /// The smallest dot product of a candidate vertex's normal and the reference's at its match: 1 when they point the same way, 0
    /// at a right angle, -1 when inside out. Vertices without a normal on either side (a mesh made without the snap) are not counted;
    /// 1 when none is.
    var smallestNormalDot: Float = 1
    /// Vertices of either mesh with none of the other's within `searchRadius`.
    var unmatched = 0

    init(reference: TriangleMesh, candidate: TriangleMesh, searchRadius: Float = 0.01) {
        let forward = Self.directed(from: candidate, to: reference, radius: searchRadius)
        let backward = Self.directed(from: reference, to: candidate, radius: searchRadius)
        farthest = max(forward.farthest, backward.farthest)
        farthestAlongNormal = forward.alongNormal
        smallestNormalDot = forward.smallestDot
        unmatched = forward.unmatched + backward.unmatched
    }

    private static func cell(_ point: SIMD3<Float>, _ radius: Float) -> SIMD3<Int32> {
        SIMD3(Int32((point.x / radius).rounded(.down)), Int32((point.y / radius).rounded(.down)), Int32((point.z / radius).rounded(.down)))
    }

    /// The dot product of the normals of `source`'s vertex `at` and `target`'s vertex `other`; `nil` when either has none (a mesh made
    /// without the snap has zero vectors).
    private static func normalDot(_ source: TriangleMesh, _ at: Int, _ target: TriangleMesh, _ other: Int) -> Float? {
        guard source.normals.indices.contains(at), target.normals.indices.contains(other) else { return nil }
        let (mine, theirs) = (source.normals[at], target.normals[other])
        guard (mine * mine).sum() > 0.25, (theirs * theirs).sum() > 0.25 else { return nil }
        return (mine * theirs).sum()
    }

    /// Each vertex of `source` against the nearest vertex of `target`.
    private static func directed(from source: TriangleMesh, to target: TriangleMesh,
                                 radius: Float) -> (farthest: Float, alongNormal: Float, smallestDot: Float, unmatched: Int) {
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for (index, point) in target.positions.enumerated() { grid[cell(point, radius), default: []].append(index) }
        var result: (farthest: Float, alongNormal: Float, smallestDot: Float, unmatched: Int) = (0, 0, 1, 0)
        for (at, point) in source.positions.enumerated() {
            let home = cell(point, radius)
            var nearest: (index: Int, distance: Float)?
            for dx in Int32(-1)...1 {
                for dy in Int32(-1)...1 {
                    for dz in Int32(-1)...1 {
                        for index in grid[home &+ SIMD3(dx, dy, dz), default: []] {
                            let offset = point - target.positions[index]
                            let distance = (offset * offset).sum().squareRoot()
                            if distance < (nearest?.distance ?? .infinity) { nearest = (index, distance) }
                        }
                    }
                }
            }
            guard let nearest else { result.unmatched += 1; continue }
            result.farthest = max(result.farthest, nearest.distance)
            if target.normals.indices.contains(nearest.index) {
                let along = abs(((point - target.positions[nearest.index]) * target.normals[nearest.index]).sum())
                result.alongNormal = max(result.alongNormal, along)
                if let dot = normalDot(source, at, target, nearest.index) { result.smallestDot = min(result.smallestDot, dot) }
            }
        }
        return result
    }
}

extension BrickMesh {
    /// The same arrays as a mesh, for `MeshTopology` and `MeshComparison`.
    var triangleMesh: TriangleMesh {
        TriangleMesh(positions: positions, normals: normals, triangles: triangles)
    }
}

/// An evaluator that only evaluates: the CPU mesher over a GPU engine's values, which is what meshing was before D13.
struct SamplesOnlyEvaluator: ImplicitBatchEvaluator {
    let inner: any ImplicitBatchEvaluator

    var engineName: String { inner.engineName }

    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await inner.evaluate(points)
    }
}
