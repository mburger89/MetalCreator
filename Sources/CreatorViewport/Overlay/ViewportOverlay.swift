import CreatorGeometry

/// Lines, points, fills and labels the host draws over the scene, on top of everything but the widgets (the sketch
/// editor's geometry, region fill and dimension values, sketcher spec §8). With a `gridPlane`, a grid on that plane
/// replaces the ground grid. The viewport never interprets it: the host builds it, the viewport draws it.
public struct ViewportOverlay: Hashable, Sendable {
    public var lines: [OverlayLine]
    public var points: [OverlayPoint]
    /// Filled triangles, drawn under the lines and points.
    public var fills: [OverlayFill]
    /// Text anchored in world space, drawn over the surface (`ViewportModel.overlayLabels()`).
    public var labels: [OverlayLabel]
    /// The plane whose grid is drawn instead of the ground grid, or `nil` for the ground grid.
    public var gridPlane: Plane?

    public init(lines: [OverlayLine] = [], points: [OverlayPoint] = [], fills: [OverlayFill] = [],
                labels: [OverlayLabel] = [], gridPlane: Plane? = nil) {
        self.lines = lines
        self.points = points
        self.fills = fills
        self.labels = labels
        self.gridPlane = gridPlane
    }

    public var isEmpty: Bool { lines.isEmpty && points.isEmpty && fills.isEmpty && labels.isEmpty && gridPlane == nil }
}
