import CreatorGeometry
import Foundation

/// Projection maths for a `CameraPose` in a viewport of a given size (spec §6.3).
/// - Clip space is Metal's: x and y in −1…1 (y up), and z in 0…1.
/// - The view looks down −Z.
/// - Screen space is points from the top-left, y down.
enum CameraMath {
    static func view(_ pose: CameraPose) -> Matrix4 {
        let r = pose.right
        let u = pose.up
        let b = pose.toEye
        let e = pose.eye
        return Matrix4(c0: SIMD4(r.x, u.x, b.x, 0), c1: SIMD4(r.y, u.y, b.y, 0), c2: SIMD4(r.z, u.z, b.z, 0),
                       c3: SIMD4(-r.dot(e), -u.dot(e), -b.dot(e), 1))
    }

    /// Near and far planes that keep a scene of `sceneRadius` around the target inside the frustum, wherever the
    /// orbit pivot has moved the target.
    static func depthRange(_ pose: CameraPose, sceneRadius: Double) -> (near: Double, far: Double) {
        let reach = max(sceneRadius, 1) * 4
        switch pose.projection {
        case .perspective:
            return (max(pose.distance * 0.01, 1e-4), pose.distance * 11 + reach)
        case .orthographic:
            return (-(pose.distance + reach), pose.distance + reach)
        }
    }

    static func projection(_ pose: CameraPose, aspect: Double, sceneRadius: Double) -> Matrix4 {
        let (near, far) = depthRange(pose, sceneRadius: sceneRadius)
        switch pose.projection {
        case .perspective:
            let f = 1 / tan(CameraPose.fieldOfView / 2)
            return Matrix4(c0: SIMD4(f / aspect, 0, 0, 0), c1: SIMD4(0, f, 0, 0),
                           c2: SIMD4(0, 0, far / (near - far), -1), c3: SIMD4(0, 0, near * far / (near - far), 0))
        case .orthographic:
            let halfHeight = pose.visibleHeight / 2
            return Matrix4(c0: SIMD4(1 / (halfHeight * aspect), 0, 0, 0), c1: SIMD4(0, 1 / halfHeight, 0, 0),
                           c2: SIMD4(0, 0, 1 / (near - far), 0), c3: SIMD4(0, 0, near / (near - far), 1))
        }
    }

    static func viewProjection(_ pose: CameraPose, size: ViewportSize, sceneRadius: Double) -> Matrix4 {
        projection(pose, aspect: size.aspect, sceneRadius: sceneRadius) * view(pose)
    }

    /// Where `point` lands on screen, or `nil` if it's at or behind a perspective eye.
    static func project(_ point: Vector3, _ pose: CameraPose, size: ViewportSize, sceneRadius: Double = 1) -> ProjectedPoint? {
        let clip = viewProjection(pose, size: size, sceneRadius: sceneRadius) * SIMD4(point.x, point.y, point.z, 1)
        guard clip.w > 1e-12 else { return nil }
        let x = clip.x / clip.w
        let y = clip.y / clip.w
        return ProjectedPoint(point: ScreenPoint((x + 1) / 2 * size.width, (1 - y) / 2 * size.height), depth: clip.z / clip.w)
    }

    /// The ray under a screen point: from the eye in perspective, parallel to the view in orthographic.
    static func ray(through point: ScreenPoint, _ pose: CameraPose, size: ViewportSize) -> Ray {
        let nx = point.x / size.width * 2 - 1
        let ny = 1 - point.y / size.height * 2
        let halfHeight = pose.visibleHeight / 2
        let halfWidth = halfHeight * size.aspect
        let onTargetPlane = pose.target + pose.right * (nx * halfWidth) + pose.up * (ny * halfHeight)
        switch pose.projection {
        case .perspective:
            let origin = pose.eye
            return Ray(origin: origin, direction: (onTargetPlane - origin).normalized ?? -pose.toEye, minimumT: 0)
        case .orthographic:
            return Ray(origin: onTargetPlane + pose.toEye * pose.distance, direction: -pose.toEye, minimumT: -.infinity)
        }
    }

    /// Millimetres per point at the target's depth.
    static func millimetresPerPoint(_ pose: CameraPose, size: ViewportSize) -> Double {
        pose.visibleHeight / max(size.height, 1)
    }
}
