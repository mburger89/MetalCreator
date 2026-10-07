/// A point or direction in model space, in millimetres.
public struct Vector3: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)
    public static let unitX = Vector3(1, 0, 0)
    public static let unitY = Vector3(0, 1, 0)
    public static let unitZ = Vector3(0, 0, 1)

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (v: Vector3, s: Double) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
    public static prefix func - (v: Vector3) -> Vector3 { Vector3(-v.x, -v.y, -v.z) }

    public func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    public var length: Double { dot(self).squareRoot() }

    /// The unit vector in the same direction, or `nil` for a (near) zero-length vector.
    public var normalized: Vector3? {
        let length = length
        return length > 1e-12 ? self * (1 / length) : nil
    }

    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
