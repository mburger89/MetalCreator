import CreatorGeometry

/// The cut view's plane (implicit spec §5.1): everything on the side `normal` points to is cut away, so the part can be seen inside its
/// skin. The host makes one and the viewport clips every solid, mesh and edge by it in the fragment shader; the cut face is the
/// inside of the part's far wall, drawn in its colour darkened.
public struct ViewportClip: Hashable, Sendable {
    public var origin: Vector3
    /// Points to the side that is cut away.
    public var normal: Vector3

    public init(origin: Vector3, normal: Vector3) {
        self.origin = origin
        self.normal = normal
    }

    /// True when the plane has a position and a direction that are numbers.
    public var isValid: Bool { origin.isFinite && normal.isFinite && normal.normalized != nil }

    /// Whether `point` is cut away.
    public func removes(_ point: Vector3) -> Bool {
        guard let unit = normal.normalized else { return false }
        return (point - origin).dot(unit) > 0
    }

    /// The plane as the shader takes it: a point is cut away when n·p + d > 0, with the unit normal n and d = −n·origin.
    var coefficients: SIMD4<Float> {
        guard let unit = normal.normalized else { return .zero }
        return SIMD4(Float(unit.x), Float(unit.y), Float(unit.z), Float(-unit.dot(origin)))
    }
}
