import CreatorDrawing
import CreatorGeometry

/// A cutting line being drawn on `parent`: `points` in the parent's model plane (DR-3 R13). A finished line waits for the click that
/// places the view.
public struct SectionDraft: Hashable, Sendable {
    public var parent: ViewID
    public var points: [Vector2]
    public var isFinished: Bool

    public init(parent: ViewID, points: [Vector2], isFinished: Bool = false) {
        self.parent = parent
        self.points = points
        self.isFinished = isFinished
    }
}

/// A detail circle being dragged out on `parent`, in the parent's model plane. A finished circle waits for the placing click.
public struct DetailDraft: Hashable, Sendable {
    public var parent: ViewID
    public var center: Vector2
    public var radius: Double
    public var isFinished: Bool

    public init(parent: ViewID, center: Vector2, radius: Double, isFinished: Bool = false) {
        self.parent = parent
        self.center = center
        self.radius = radius
        self.isFinished = isFinished
    }
}

/// The edge an auxiliary view will look square to: its midpoint `at` and unit direction `along`, in the parent's model plane.
public struct AuxiliaryDraft: Hashable, Sendable {
    public var parent: ViewID
    public var at: Vector2
    public var along: Vector2

    public init(parent: ViewID, at: Vector2, along: Vector2) {
        self.parent = parent
        self.at = at
        self.along = along
    }
}
