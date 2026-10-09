import CreatorGeometry

/// The camera and view size one piece of input was made in, for a `ViewportTool`: screen points to rays, to points
/// on a plane, and back (spec §6.3's projection maths, read-only). Screen points are viewport points, y down.
public struct ViewportProjector: Hashable, Sendable {
    public var pose: CameraPose
    public var size: ViewportSize
    /// The model area: how far floating panels cover the view's edges (`ViewportModel.modelArea`, as far as the view
    /// can honour it), so a tool keeps what it draws on screen (the sketch's readout) clear of them.
    public var modelArea: ViewportInsets

    public init(pose: CameraPose, size: ViewportSize, modelArea: ViewportInsets = ViewportInsets()) {
        self.pose = pose
        self.size = size
        self.modelArea = modelArea
    }

    /// Millimetres per point at the target's depth (everywhere, in orthographic).
    public var millimetresPerPoint: Double { CameraMath.millimetresPerPoint(pose, size: size) }

    /// Where the ray under `point` meets `plane`, in the plane's own (x, y) coordinates; `nil` for an empty view, a
    /// plane seen edge-on, or (in perspective) a plane behind the eye.
    public func planePoint(under point: ScreenPoint, on plane: Plane) -> Vector2? {
        guard !size.isEmpty, point.x.isFinite, point.y.isFinite, let normal = plane.normal.normalized else { return nil }
        let ray = CameraMath.ray(through: point, pose, size: size)
        let facing = normal.dot(ray.direction)
        guard abs(facing) > 1e-9 else { return nil }
        let t = normal.dot(plane.origin - ray.origin) / facing
        guard t >= ray.minimumT, t.isFinite else { return nil }
        let offset = ray.point(at: t) - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }

    /// Where a world point lands on screen, or `nil` at or behind a perspective eye.
    public func screenPoint(of world: Vector3) -> ScreenPoint? {
        CameraMath.project(world, pose, size: size)?.point
    }
}
