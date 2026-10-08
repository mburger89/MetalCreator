import CreatorGeometry

/// Hit-testing and dragging in-view handles (spec §6.5).
enum HandleMath {
    /// How close, in points, the pointer must be to a knob to grab it.
    static let knobRadius = 10.0

    /// The handle whose knob is nearest `point`, if any is within `knobRadius`.
    static func hit(_ handles: [ViewportHandle], at point: ScreenPoint, pose: CameraPose, size: ViewportSize) -> ViewportHandle? {
        guard !size.isEmpty else { return nil }
        var best: (handle: ViewportHandle, distance: Double)?
        for handle in handles {
            guard let knob = CameraMath.project(handle.knob, pose, size: size)?.point else { continue }
            let distance = (knob - point).length
            if distance <= knobRadius, distance < (best?.distance ?? .infinity) { best = (handle, distance) }
        }
        return best?.handle
    }

    /// The value after dragging from `start` to `current`. The pointer's motion is projected onto the handle's
    /// axis on screen, and the result is clamped to the handle's range. A handle pointing within about 8.5° of the
    /// view axis can't be dragged: on screen it's too short for pointer motion to mean anything, and dividing by its
    /// length would jump the value.
    /// The knob follows the pointer: the motion along the axis, in millimetres, is divided by the handle's `scale`.
    static func value(for handle: ViewportHandle, startValue: Double, from start: ScreenPoint, to current: ScreenPoint,
                      pose: CameraPose, size: ViewportSize) -> Double {
        guard !size.isEmpty, let axis = handle.direction.normalized,
              let a = CameraMath.project(handle.anchor, pose, size: size)?.point,
              let b = CameraMath.project(handle.anchor + axis, pose, size: size)?.point else { return startValue }
        let screenAxis = b - a
        let lengthSquared = screenAxis.x * screenAxis.x + screenAxis.y * screenAxis.y
        let fullScale = 1 / CameraMath.millimetresPerPoint(pose, size: size)
        guard lengthSquared >= (0.15 * fullScale) * (0.15 * fullScale), handle.scale != 0 else { return startValue }
        let delta = current - start
        let value = startValue + (delta.x * screenAxis.x + delta.y * screenAxis.y) / lengthSquared / handle.scale
        guard value.isFinite else { return startValue }
        return min(max(value, handle.range.lowerBound), handle.range.upperBound)
    }
}
