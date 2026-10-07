/// An oriented plane: an origin, a unit normal, and a unit in-plane x axis.
/// The in-plane y axis is `normal × xAxis`, so (xAxis, yAxis, normal) is right-handed.
public struct Plane: Hashable, Sendable, Codable {
    public var origin: Vector3
    public var normal: Vector3
    public var xAxis: Vector3

    public init(origin: Vector3, normal: Vector3, xAxis: Vector3) {
        self.origin = origin
        self.normal = normal
        self.xAxis = xAxis
    }

    public var yAxis: Vector3 { normal.cross(xAxis) }

    /// The ground plane. Local (x, y) → world (x, y).
    public static let xy = Plane(origin: .zero, normal: .unitZ, xAxis: .unitX)
    /// The front plane. Local (x, y) → world (x, z).
    public static let xz = Plane(origin: .zero, normal: -.unitY, xAxis: .unitX)
    /// The side plane. Local (x, y) → world (y, z).
    public static let yz = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)

    /// An XY-oriented plane through `point`, used when a vector is wired into a plane socket.
    public static func through(_ point: Vector3) -> Plane {
        Plane(origin: point, normal: .unitZ, xAxis: .unitX)
    }

    /// The world position of local plane coordinates `p`.
    public func point(_ p: Vector2) -> Vector3 { origin + xAxis * p.x + yAxis * p.y }

    /// This plane moved `distance` along its normal.
    public func offset(by distance: Double) -> Plane {
        Plane(origin: origin + normal * distance, normal: normal, xAxis: xAxis)
    }
}
