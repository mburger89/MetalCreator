import CreatorGeometry

/// Lines and points the host draws over the scene, on top of everything but the widgets (the sketch editor's
/// geometry, sketcher spec §8). With a `gridPlane`, a grid on that plane replaces the ground grid. The viewport
/// never interprets it: the host builds it, the viewport draws it.
public struct ViewportOverlay: Hashable, Sendable {
    public var lines: [OverlayLine]
    public var points: [OverlayPoint]
    /// The plane whose grid is drawn instead of the ground grid, or `nil` for the ground grid.
    public var gridPlane: Plane?

    public init(lines: [OverlayLine] = [], points: [OverlayPoint] = [], gridPlane: Plane? = nil) {
        self.lines = lines
        self.points = points
        self.gridPlane = gridPlane
    }

    public var isEmpty: Bool { lines.isEmpty && points.isEmpty && gridPlane == nil }
}
