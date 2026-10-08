import CreatorGeometry

/// A camera move in progress (spec §6.3: about 250 ms to a view-cube face). The model keeps `to` as its
/// committed pose and draws `pose(at:)`. Smoothstep easing. Yaw takes the short way round. The projection
/// switches at the start.
struct CameraAnimation: Equatable, Sendable {
    var from: CameraPose
    var to: CameraPose
    var start: Double
    var duration: Double

    static let viewCubeDuration = 0.25

    func pose(at time: Double) -> CameraPose {
        let raw = duration > 0 ? (time - start) / duration : 1
        let t = min(max(raw, 0), 1)
        if t >= 1 { return to }
        let s = t * t * (3 - 2 * t)
        var pose = to
        pose.target = from.target + (to.target - from.target) * s
        pose.distance = from.distance + (to.distance - from.distance) * s
        pose.yaw = from.yaw + (to.yaw - from.yaw).remainder(dividingBy: 2 * .pi) * s
        pose.pitch = from.pitch + (to.pitch - from.pitch) * s
        return pose
    }
}
