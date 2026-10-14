import CreatorGeometry

/// A rigid move as a frame: where the local origin goes and the world directions of the local axes (orthonormal, right-handed).
/// Place on implicits (implicit spec §3.3) turns each placement plane into one, exactly as `Plane.placement` does for solids: the
/// shape, built at the origin facing +Z, ends up on the plane facing along its normal.
public struct RigidMove: Hashable, Sendable {
    public var origin: Vector3
    public var xAxis: Vector3
    public var yAxis: Vector3
    public var zAxis: Vector3

    public init(origin: Vector3, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    public static let identity = RigidMove(origin: .zero, xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)

    /// The move onto `plane`: +X to its x axis (made perpendicular to the normal first), +Z to its normal. `nil` for a plane with no
    /// usable direction (a zero or non-finite normal, an x axis along the normal, a non-finite origin).
    public init?(plane: Plane) {
        guard plane.origin.isFinite, plane.normal.isFinite, plane.xAxis.isFinite, let z = plane.normal.normalized,
              let x = (plane.xAxis - z * plane.xAxis.dot(z)).normalized else { return nil }
        self.init(origin: plane.origin, xAxis: x, yAxis: z.cross(x), zAxis: z)
    }

    /// Where the local point goes.
    public func toWorld(_ local: Vector3) -> Vector3 {
        origin + xAxis * local.x + yAxis * local.y + zAxis * local.z
    }

    /// The local point that goes to `world`.
    public func toLocal(_ world: Vector3) -> Vector3 {
        let offset = world - origin
        return Vector3(offset.dot(xAxis), offset.dot(yAxis), offset.dot(zAxis))
    }

    /// The box that contains the move of every corner of `box`.
    public func bounds(of box: BoundingBox) -> BoundingBox {
        let corners = (0..<8).map { bit in
            toWorld(Vector3(bit & 1 == 0 ? box.min.x : box.max.x, bit & 2 == 0 ? box.min.y : box.max.y,
                            bit & 4 == 0 ? box.min.z : box.max.z))
        }
        return BoundingBox(points: corners) ?? box
    }
}
