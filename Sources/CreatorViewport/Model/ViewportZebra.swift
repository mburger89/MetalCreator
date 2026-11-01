import CreatorGeometry
import Foundation

/// The zebra stripes view mode: the viewport's own value (it never sees the graph's `ZebraSettings`). Stripes show where a
/// surface's reflection of the view direction changes angle, so a kink in curvature shows as a kink in a stripe.
public struct ViewportZebra: Hashable, Sendable {
    public enum Direction: Sendable { case horizontal, vertical }

    /// The pose a locked zebra is measured against, in world space.
    public struct Frame: Hashable, Sendable {
        public var right: Vector3
        public var up: Vector3
        public var toEye: Vector3

        public init(right: Vector3, up: Vector3, toEye: Vector3) {
            self.right = right
            self.up = up
            self.toEye = toEye
        }
    }

    public var direction: Direction
    /// Periods over the full turn of the reflection's angle.
    public var stripes: Int
    /// The share of each period that is black, 0...1.
    public var blackShare: Double
    /// The locked frame, or `nil` to follow the camera.
    public var lock: Frame?

    public init(direction: Direction, stripes: Int, blackShare: Double, lock: Frame? = nil) {
        self.direction = direction
        self.stripes = stripes
        self.blackShare = blackShare
        self.lock = lock
    }
}

/// The CPU twin of the shaders' stripe function (plan Ruling 1); the shaders are tested against it.
public enum ZebraBand {
    /// 0 for black, 1 for white. `normal` and `toEye` are in the same space as `right`, `up` and `back`, the axes the angle is
    /// measured in (the view's, or a locked frame's).
    public static func value(normal: Vector3, toEye: Vector3, right: Vector3, up: Vector3, back: Vector3,
                             zebra: ViewportZebra) -> Double {
        let n = normal
        let reflection = n * (2 * n.dot(toEye)) - toEye
        let across = zebra.direction == .vertical ? reflection.dot(right) : reflection.dot(up)
        let theta = atan2(across, reflection.dot(back))
        let phase = theta * Double(zebra.stripes) / (2 * Double.pi)
        let fraction = phase - phase.rounded(.down)
        return fraction < zebra.blackShare ? 0 : 1
    }
}
