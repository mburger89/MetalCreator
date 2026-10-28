/// What a dimension measures, in world space (millimetres), independent of the camera.
public enum DimensionGeometry: Sendable, Hashable {
    /// A length from `from` to `to`, measured along `direction`, drawn on the `side` of the geometry.
    case linear(from: Vector3, to: Vector3, direction: Vector3, side: Vector3, placement: DimensionPlacement)
    /// A radius or diameter of the circle round `center` in the plane with `normal`; the leader aims `toward`.
    case radial(center: Vector3, radius: Double, normal: Vector3, toward: Vector3, placement: DimensionPlacement)
    /// The angle at `vertex` between the rays through `first` and `second`, in the plane with `normal`.
    case angular(vertex: Vector3, first: Vector3, second: Vector3, normal: Vector3, placement: DimensionPlacement)

    /// The normal of the plane the dimension lies in (not normalised for a linear one: `direction × side`).
    public var planeNormal: Vector3 {
        switch self {
        case let .linear(_, _, direction, side, _): direction.cross(side)
        case let .radial(_, _, normal, _, _): normal
        case let .angular(_, _, _, normal, _): normal
        }
    }
}
