import Foundation

/// Where the viewport camera is (spec §6.3): a turntable around `target` with Z up. `yaw` 0 looks from the front
/// (from −Y towards +Y), and positive yaw swings the eye towards +X. `pitch` is the eye's elevation: π/2 looks
/// straight down with +Y up on screen. The viewport clamps it to ±π/2. Angles are radians. Saved in the
/// document's view state.
public struct CameraPose: Hashable, Sendable, Codable {
    public var target: Vector3
    /// Millimetres from the target to the eye. In orthographic projection it sets the zoom through `visibleHeight`.
    public var distance: Double
    public var yaw: Double
    public var pitch: Double
    public var projection: Projection

    public init(target: Vector3 = .zero, distance: Double = 200, yaw: Double = 0, pitch: Double = 0,
                projection: Projection = .perspective) {
        self.target = target
        self.distance = distance
        self.yaw = yaw
        self.pitch = pitch
        self.projection = projection
    }

    /// The vertical field of view of the perspective projection.
    public static let fieldOfView = 40.0 * Double.pi / 180

    /// The unit vector from the target towards the eye.
    public var toEye: Vector3 { Vector3(sin(yaw) * cos(pitch), -cos(yaw) * cos(pitch), sin(pitch)) }
    /// Screen right, in world space. It's horizontal, and defined at the poles too.
    public var right: Vector3 { Vector3(cos(yaw), sin(yaw), 0) }
    /// Screen up, in world space. (`right`, `up`, `toEye`) is right-handed.
    public var up: Vector3 { toEye.cross(right) }
    public var eye: Vector3 { target + toEye * distance }
    /// The height of the view in mm at the target's depth. Orthographic projection uses it at every depth, so
    /// switching projection keeps the framing.
    public var visibleHeight: Double { 2 * distance * tan(Self.fieldOfView / 2) }

    /// True when every field is finite and the distance is positive: the pose can be drawn and saved.
    public var isFinite: Bool {
        target.isFinite && distance.isFinite && distance > 0 && yaw.isFinite && pitch.isFinite
    }
}
