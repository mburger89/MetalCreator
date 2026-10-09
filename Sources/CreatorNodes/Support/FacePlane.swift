import CreatorGeometry

/// The plane a Plane from Face node puts on a flat face (sketcher spec §7).
enum FacePlane {
    /// World X counts as "nearly parallel" to the normal when its in-plane part is shorter than this.
    static let parallelLimit = 1e-3

    /// A plane through `origin` facing `normal` (unit). Its x axis is world X projected onto the face, or
    /// world Y projected when X is nearly parallel to the normal, so it is deterministic.
    static func plane(origin: Vector3, normal: Vector3) -> Plane {
        func inPlane(_ axis: Vector3) -> Vector3 { axis - normal * axis.dot(normal) }
        let projectedX = inPlane(.unitX)
        let xAxis = projectedX.length >= parallelLimit ? projectedX : inPlane(.unitY)
        return Plane(origin: origin, normal: normal, xAxis: xAxis.normalized ?? .unitX)
    }
}
