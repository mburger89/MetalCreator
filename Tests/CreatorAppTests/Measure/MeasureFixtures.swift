import CreatorGeometry
import CreatorKernel

@testable import CreatorApp

enum MeasureFixtures {
    static func face(_ id: Int, _ kind: SurfaceKind = .plane, normal: Vector3? = nil, area: Double = 1, radius: Double? = nil,
                     axisPoint: Vector3? = nil, centroid: Vector3 = .zero) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: kind, normal: normal, area: area, centroid: centroid, tags: [], radius: radius,
                 axisPoint: axisPoint)
    }

    static func line(_ id: Int, from a: Vector3, to b: Vector3) -> EdgeInfo {
        let delta = b - a
        return EdgeInfo(id: EdgeID(id), kind: .line, direction: delta.normalized, length: delta.length, midpoint: (a + b) * 0.5,
                        convexity: .convex, faces: [], curve: .line(start: a, end: b))
    }

    static func circle(_ id: Int, centre: Vector3 = .zero, radius: Double, sweep: Double) -> EdgeInfo {
        let start = centre + Vector3(radius, 0, 0)
        return EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitZ, length: radius * sweep, midpoint: start,
                        convexity: .convex, faces: [],
                        curve: .circle(center: centre, axis: .unitZ, radius: radius, start: start, sweep: sweep))
    }

    static func topology(faces: [FaceInfo] = [], edges: [EdgeInfo] = []) -> [Int: Topology] {
        [0: Topology(faces: faces, edges: edges)]
    }
}
