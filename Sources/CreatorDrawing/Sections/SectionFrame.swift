import CreatorGeometry
import CreatorKernel

/// A section's frame, side and alignment (R3).
public enum SectionFrame {
    /// The frame of a section cut along `t` (the first segment's unit direction in the parent's plane) looking toward `v`.
    public static func frame(parent: ProjectionFrame, along t: Vector2, viewing v: Vector2) -> ProjectionFrame {
        let r = parent.right, u = parent.up
        let t3 = r * t.x + u * t.y
        let s3 = r * v.x + u * v.y
        if abs(t.x) >= abs(t.y) {
            let along = t3 * (t.x < 0 ? -1 : 1)
            return ProjectionFrame(direction: s3, up: along.cross(s3))
        }
        let along = t3 * (t.y < 0 ? -1 : 1)
        return ProjectionFrame(direction: s3, up: along)
    }

    public static func frame(for cutter: SectionCutter) -> ProjectionFrame {
        frame(parent: cutter.frame, along: cutter.direction, viewing: cutter.viewing)
    }

    /// The direction a section looks: toward the drop point for first angle, away from it for third angle.
    public static func viewing(
        along t: Vector2, from origin: Vector2, drop: Vector2, standard: DrawingStandard
    ) -> Vector2 {
        let normal = Vector2(-t.y, t.x)
        let offset = drop - origin
        let sigma: Double = offset.x * normal.x + offset.y * normal.y >= 0 ? 1 : -1
        return normal * (standard.isFirstAngle ? sigma : -sigma)
    }

    /// A horizontal line gives a section aligned vertically with its parent, a vertical one horizontally, a slanted one none.
    public static func alignment(along t: Vector2) -> AlignmentAxis? {
        let length = t.length
        guard length > 0 else { return nil }
        if abs(t.y) <= 1e-9 * length { return .vertical }
        if abs(t.x) <= 1e-9 * length { return .horizontal }
        return nil
    }
}
