import CreatorGeometry

/// A closed filled polygon on the sheet, in sheet millimetres: an arrowhead (plan R16).
public struct SheetFill: Hashable, Sendable {
    public var points: [Vector2]
    public var layer: DrawingLayer
    public var view: ViewID?
    public var annotation: AnnotationID?
    public var isLost: Bool
    /// The derived view whose arrowhead this is (DR-3 R6), `nil` for everything else.
    public var mark: ViewID?

    public init(
        points: [Vector2], layer: DrawingLayer = .dimension, view: ViewID? = nil, annotation: AnnotationID? = nil,
        isLost: Bool = false, mark: ViewID? = nil
    ) {
        self.mark = mark
        self.points = points
        self.layer = layer
        self.view = view
        self.annotation = annotation
        self.isLost = isLost
    }
}
