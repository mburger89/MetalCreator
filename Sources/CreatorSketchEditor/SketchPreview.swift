import CreatorGeometry

/// What the active tool shows before it commits: its rubber-band curves and the points it has placed, in plane
/// coordinates. Empty when nothing is in progress.
public struct SketchPreview: Hashable, Sendable {
    public var curves: [PreviewCurve]
    public var points: [Vector2]

    public init(curves: [PreviewCurve] = [], points: [Vector2] = []) {
        self.curves = curves
        self.points = points
    }

    public static let none = SketchPreview()
}
