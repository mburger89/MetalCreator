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
    /// The largest ratio of a candidate vertex's distance along the reference's normal to its allowed distance
    /// (`allowance(slope:)`), over the vertices with a slope; 0 when `slopes` is empty. At most 1 passes (spec erratum D17).
    var worstScaledSurface: Float = 0
    /// That vertex's distance along the normal and its allowed distance, for the report.
    var worstScaledDetail: (along: Float, allowed: Float) = (0, 1e-4)
    /// Vertices of either mesh with none of the other's within `searchRadius`.
    var unmatched = 0

    /// The surface distance allowed where the field's slope (the magnitude of its gradient) is `slope`: 1e-4 mm divided by the slope,
    /// never less than 1e-4 mm (a value difference of 1e-4 moves the surface 1e-4 / slope).
    static func allowance(slope: Float) -> Float {
        1e-4 * max(1, 1 / max(slope, 1e-6))
    }

    /// `slopes` holds the field's slope at each of the reference's vertices (same order), for the scaled surface check. A vertex of
    /// either mesh for which `excluding` is true is not compared (its match is not looked for, and it is not counted as unmatched): the
    /// GPU mesh comparison leaves out the neighbourhood of a mapping's singular set (spec Errata D20).
    init(reference: TriangleMesh, candidate: TriangleMesh, searchRadius: Float = 0.01, slopes: [Float] = [],
         excluding: (SIMD3<Float>) -> Bool = { _ in false }) {
        let forward = Self.directed(from: candidate, to: reference, radius: searchRadius, slopes: slopes, excluding: excluding)
        worstScaledSurface = forward.ratio
        worstScaledDetail = (forward.along, forward.allowed)
        let backward = Self.directed(from: reference, to: candidate, radius: searchRadius, slopes: [], excluding: excluding)
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

    /// What one direction of the comparison found.
    private struct Directed {
        var farthest: Float = 0
        var alongNormal: Float = 0
        var smallestDot: Float = 1
        var unmatched = 0
        var ratio: Float = 0
        var along: Float = 0
        var allowed: Float = 1e-4
    }

    /// The vertex of `target` nearest to `point`, with its distance, found through the grid.
    private static func nearest(to point: SIMD3<Float>, in grid: [SIMD3<Int32>: [Int]], of target: TriangleMesh,
                                radius: Float) -> (index: Int, distance: Float)? {
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
        return nearest
    }

    /// Each vertex of `source` against the nearest vertex of `target`, except those `excluding` says to leave out.
    private static func directed(from source: TriangleMesh, to target: TriangleMesh, radius: Float, slopes: [Float],
                                 excluding: (SIMD3<Float>) -> Bool) -> Directed {
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for (index, point) in target.positions.enumerated() { grid[cell(point, radius), default: []].append(index) }
        var result = Directed()
        for (at, point) in source.positions.enumerated() where !excluding(point) {
            guard let nearest = nearest(to: point, in: grid, of: target, radius: radius) else { result.unmatched += 1; continue }
            result.farthest = max(result.farthest, nearest.distance)
            guard target.normals.indices.contains(nearest.index) else { continue }
            let along = abs(((point - target.positions[nearest.index]) * target.normals[nearest.index]).sum())
            result.alongNormal = max(result.alongNormal, along)
            if slopes.indices.contains(nearest.index) {
                let allowed = allowance(slope: slopes[nearest.index])
                if along / allowed > result.ratio { (result.ratio, result.along, result.allowed) = (along / allowed, along, allowed) }
            }
            if let dot = normalDot(source, at, target, nearest.index) { result.smallestDot = min(result.smallestDot, dot) }
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
