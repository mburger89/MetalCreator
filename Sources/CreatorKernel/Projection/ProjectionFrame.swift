import CreatorGeometry

/// How a view looks at the model (drawings spec, R5): `direction` is the way the viewer looks, `up` the page's up, both unit and
/// perpendicular. A model point p lands at (p . right, p . up).
public struct ProjectionFrame: Hashable, Sendable, Codable {
    public let direction: Vector3
    public let up: Vector3

    public init(direction: Vector3, up: Vector3) {
        self.direction = direction
        self.up = up
    }

    public var right: Vector3 { direction.cross(up) }

    public func place(_ p: Vector3) -> Vector2 { Vector2(p.dot(right), p.dot(up)) }

    /// A frame looking along `direction` with `up` made perpendicular to it; `nil` when either is zero or they are parallel.
    public static func make(direction: Vector3, up: Vector3) -> ProjectionFrame? {
        guard let unit = direction.normalized else { return nil }
        // Normalise `up` first, so the parallel test reads the angle and not the length of `up`.
        guard let upUnit = up.normalized else { return nil }
        let residual = upUnit - unit * upUnit.dot(unit)
        guard residual.length > 1e-9, let flat = residual.normalized else { return nil }
        return ProjectionFrame(direction: unit, up: flat)
    }

    public func validate() throws(KernelError) {
        let unit = abs(direction.length - 1) <= 1e-9 && abs(up.length - 1) <= 1e-9
        guard unit, abs(direction.dot(up)) <= 1e-9 else {
            throw KernelError.invalidInput("The view direction and its up direction must be perpendicular unit vectors.")
        }
    }
}
