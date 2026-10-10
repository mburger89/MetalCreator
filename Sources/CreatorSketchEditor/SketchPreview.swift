import CreatorGeometry

/// What the active tool shows before it commits: its rubber-band curves and the points it has placed, in plane
/// coordinates, and the constraints the next click would infer (their glyphs go by the pointer). Empty when nothing
/// is in progress.
public struct SketchPreview: Hashable, Sendable {
    public var curves: [PreviewCurve]
    public var points: [Vector2]
    /// What the next click would infer: coincident (on a point), point on (on a curve), horizontal, vertical or
    /// tangent (a line's end).
    public var inferred: [SketchConstraintKind]

    public init(curves: [PreviewCurve] = [], points: [Vector2] = [], inferred: [SketchConstraintKind] = []) {
        self.curves = curves
        self.points = points
        self.inferred = inferred
    }

    public static let none = SketchPreview()
}
