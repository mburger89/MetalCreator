import CreatorGeometry
import Foundation

/// Pure camera moves (spec §6.3): orbit about a pivot, pan, zoom toward the cursor, frame bounds, and look
/// from a direction. Every function returns a new pose and never makes a non-finite one from finite input.
enum CameraNavigation {
    static let minimumDistance = 1e-3
    static let maximumDistance = 1e6

    /// Turntable orbit by a pointer delta in points. With a `pivot`, the camera moves so the pivot stays at the
    /// same place on screen (spec: "orbit pivots on the point under the cursor").
    static func orbit(_ pose: CameraPose, dx: Double, dy: Double, pivot: Vector3?) -> CameraPose {
        var next = pose
        next.yaw = (pose.yaw - dx * ViewportInputMap.orbitRadiansPerPoint).remainder(dividingBy: 2 * .pi)
        next.pitch = min(max(pose.pitch + dy * ViewportInputMap.orbitRadiansPerPoint, -.pi / 2), .pi / 2)
        guard let pivot else { return next }
        let offset = pose.target - pivot
        let (r, u, b) = (offset.dot(pose.right), offset.dot(pose.up), offset.dot(pose.toEye))
        next.target = pivot + next.right * r + next.up * u + next.toEye * b
        return next
    }

    /// Moves the target so the scene follows the pointer by (`dx`, `dy`) points at the target's depth.
    static func pan(_ pose: CameraPose, dx: Double, dy: Double, size: ViewportSize) -> CameraPose {
        guard !size.isEmpty else { return pose }
        let scale = CameraMath.millimetresPerPoint(pose, size: size)
        var next = pose
        next.target = pose.target - pose.right * (dx * scale) + pose.up * (dy * scale)
        return next
    }

    /// Divides the distance by `factor` (more than 1 zooms in). With a point, the model point under it, on the
    /// plane through the target, stays under it.
    static func zoom(_ pose: CameraPose, factor: Double, toward point: ScreenPoint?, size: ViewportSize) -> CameraPose {
        guard factor.isFinite, factor > 0 else { return pose }
        var next = pose
        next.distance = min(max(pose.distance / factor, minimumDistance), maximumDistance)
        guard let point, !size.isEmpty, point.x.isFinite, point.y.isFinite else { return next }
        let before = CameraMath.millimetresPerPoint(pose, size: size)
        let after = CameraMath.millimetresPerPoint(next, size: size)
        let offset = point - size.center
        next.target = pose.target + (pose.right * offset.x - pose.up * offset.y) * (before - after)
        return next
    }

    /// Centres `bounds` in the model area (the view less `insets`, spec §6.3) and backs off until its bounding
    /// sphere fits that area with `margin`, keeping the orientation and projection. Insets the view can't honour are
    /// ignored (`ViewportInsets.usable(in:)`). A point or flat box still gets a usable distance. Non-finite bounds
    /// change nothing.
    static func frame(_ bounds: BoundingBox, _ pose: CameraPose, size: ViewportSize, insets: ViewportInsets = ViewportInsets(),
                      margin: Double = 1.1) -> CameraPose {
        guard bounds.min.isFinite, bounds.max.isFinite else { return pose }
        let area = insets.usable(in: size)
        let radius = max(bounds.size.length / 2, 0.5)
        // The area's width and height in units of the view's height: the tangent of an angle across it.
        let high = size.isEmpty ? 1 : (size.height - area.top - area.bottom) / size.height
        let wide = size.isEmpty ? size.aspect : (size.width - area.leading - area.trailing) / size.height
        let tanHalf = tan(CameraPose.fieldOfView / 2)
        let halfVertical = atan(tanHalf * high)
        let halfHorizontal = atan(tanHalf * wide)
        var next = pose
        next.distance = min(max(radius * margin / sin(min(halfVertical, halfHorizontal)), minimumDistance), maximumDistance)
        // The target sits at the view's centre; move it so the bounds' centre lands on the area's centre instead.
        let scale = CameraMath.millimetresPerPoint(next, size: size)
        let offsetX = (area.leading - area.trailing) / 2
        let offsetY = (area.top - area.bottom) / 2
        next.target = bounds.center - next.right * (offsetX * scale) + next.up * (offsetY * scale)
        return next
    }

    /// Yaw and pitch that look from `direction` (the eye placed along it). Straight up or down keeps
    /// `fallbackYaw`. A zero vector has no orientation.
    static func orientation(lookingFrom direction: Vector3, fallbackYaw: Double) -> (yaw: Double, pitch: Double)? {
        guard let d = direction.normalized else { return nil }
        let pitch = asin(min(max(d.z, -1), 1))
        let horizontal = (d.x * d.x + d.y * d.y).squareRoot()
        return (horizontal > 1e-9 ? atan2(d.x, -d.y) : fallbackYaw, pitch)
    }

    /// One arrow press. Left and right turn 90° about Z. Up and down tilt 90°, and going past a pole carries on
    /// to the face behind (front → top → back).
    static func rotate(_ pose: CameraPose, _ arrow: CubeArrow) -> CameraPose {
        let quarter = Double.pi / 2
        var next = pose
        switch arrow {
        case .left:
            next.yaw = (pose.yaw - quarter).remainder(dividingBy: 2 * .pi)
        case .right:
            next.yaw = (pose.yaw + quarter).remainder(dividingBy: 2 * .pi)
        case .up:
            let pitch = pose.pitch + quarter
            if pitch > quarter + 1e-9 {
                next.yaw = (pose.yaw + .pi).remainder(dividingBy: 2 * .pi)
                next.pitch = .pi - pitch
            } else {
                next.pitch = min(pitch, quarter)
            }
        case .down:
            let pitch = pose.pitch - quarter
            if pitch < -quarter - 1e-9 {
                next.yaw = (pose.yaw + .pi).remainder(dividingBy: 2 * .pi)
                next.pitch = -.pi - pitch
            } else {
                next.pitch = max(pitch, -quarter)
            }
        }
        return next
    }
}
