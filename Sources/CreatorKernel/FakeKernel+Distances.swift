import CreatorGeometry

extension FakeKernel {
    /// The Fake's distances (fields spec §3.1): exact for a box (the Fake's solids are bounding boxes), for planar faces
    /// measured to their infinite plane, and for straight or circular edges. Everything else is unsupported.
    static func measure(_ points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double] {
        try target.validate()
        switch target {
        case .solid(let solid):
            return points.map { boxDistance($0, solid.bounds, signed: signed) }
        case .faces(let set):
            let found = Set(set.faces.map(\.rawValue)).sorted().compactMap { set.solid.topology.face(FaceID($0)) }
            let planes = found.compactMap { face -> (origin: Vector3, normal: Vector3)? in
                guard face.kind == .plane, let normal = face.normal?.normalized else { return nil }
                return (face.centroid, normal)
            }
            guard planes.count == found.count else { throw KernelError.unsupported("distance to a curved face") }
            return points.map { point in planes.map { abs($0.normal.dot(point - $0.origin)) }.min() ?? .infinity }
        case .edges(let set):
            let found = Set(set.edges.map(\.rawValue)).sorted().compactMap { set.solid.topology.edge(EdgeID($0)) }
            let curves = found.compactMap(\.curve)
            guard curves.count == found.count else {
                throw KernelError.unsupported("distance to an edge that isn't straight or circular")
            }
            return points.map { point in curves.map { $0.distance(from: point) }.min() ?? .infinity }
        }
    }

    /// The distance to a box's surface: negative inside when `signed`, else its size.
    static func boxDistance(_ point: Vector3, _ box: BoundingBox, signed: Bool) -> Double {
        let center = box.center
        let half = box.size * 0.5
        let (qx, qy, qz) = (abs(point.x - center.x) - half.x, abs(point.y - center.y) - half.y, abs(point.z - center.z) - half.z)
        let outside = Vector3(max(qx, 0), max(qy, 0), max(qz, 0)).length
        let distance = outside + min(max(qx, max(qy, qz)), 0)
        return signed ? distance : abs(distance)
    }
}
