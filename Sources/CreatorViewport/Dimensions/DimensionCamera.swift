import CreatorGeometry
import Foundation

/// A camera pose and a viewport size: what the dimension layout needs to know about the view.
struct DimensionCamera {
    var pose: CameraPose
    var size: ViewportSize

    /// Where `point` lands on screen, or `nil` if it is at or behind a perspective eye or not finite.
    func project(_ point: Vector3) -> ScreenPoint? {
        guard point.isFinite, let projected = CameraMath.project(point, pose, size: size), projected.point.x.isFinite,
              projected.point.y.isFinite else { return nil }
        return projected.point
    }

    /// The unit vector from `point` towards the eye (parallel in orthographic projection).
    func viewDirection(at point: Vector3) -> Vector3? {
        switch pose.projection {
        case .orthographic: pose.toEye
        case .perspective: (pose.eye - point).normalized
        }
    }

    /// Screen points covered by one millimetre at `point` along the unit world direction `direction`, or `nil` when
    /// either end of that millimetre cannot be projected.
    func pointsPerMillimetre(at point: Vector3, along direction: Vector3) -> Double? {
        guard let start = project(point), let end = project(point + direction) else { return nil }
        let length = (end - start).length
        return length.isFinite ? length : nil
    }
}
