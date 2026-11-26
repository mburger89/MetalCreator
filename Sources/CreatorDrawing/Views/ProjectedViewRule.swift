import CreatorGeometry
import CreatorKernel

/// How a drop beside a parent view becomes a projected view's frame and alignment (plan R6).
public enum ProjectedViewRule {
    public static func view(
        from parent: ProjectionFrame, dropOffset: Vector2, standard: DrawingStandard
    ) -> (frame: ProjectionFrame, axis: AlignmentAxis) {
        let d = parent.direction, u = parent.up, r = parent.right
        let first = standard.isFirstAngle
        func flip(_ v: Vector3) -> Vector3 { v * -1 }
        if abs(dropOffset.x) >= abs(dropOffset.y) {
            let toRight = dropOffset.x >= 0
            // First angle looks along r for a view on the right; third angle looks the other way.
            let along = (toRight == first) ? r : flip(r)
            return (ProjectionFrame(direction: along, up: u), .horizontal)
        }
        let above = dropOffset.y > 0
        if above {
            return first
                ? (ProjectionFrame(direction: u, up: flip(d)), .vertical)
                : (ProjectionFrame(direction: flip(u), up: d), .vertical)
        }
        return first
            ? (ProjectionFrame(direction: flip(u), up: d), .vertical)
            : (ProjectionFrame(direction: u, up: flip(d)), .vertical)
    }

    public static let detailSentence = "A projected view comes from a whole view, not a detail."
    public static let axisSentence =
        "A projected view comes from a view that looks along an axis, not from an auxiliary view or a slanted section."

    /// The sentence that refuses a parent (R11): a detail, a section or auxiliary view whose frame runs along no axis, or a base or
    /// projected view that is isometric; `nil` when a projected view may come from it.
    public static func refusal(for parent: DrawingView) -> String? {
        switch parent.kind {
        case .detail: detailSentence
        case .section, .auxiliary: parent.orientation.isIsometric ? axisSentence : nil
        case .base, .projected:
            parent.orientation.isIsometric
                ? "A projected view comes from a front, side, top or bottom view, not an isometric one." : nil
        }
    }
}
