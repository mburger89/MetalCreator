import CreatorGeometry

/// One plain click on a `ClickTarget`, remembered so the next can be told a double click (`EditorModel+DoubleClick`).
struct RecentClick: Hashable, Sendable {
    var target: ClickTarget
    /// Where it was, in canvas-local screen points.
    var point: Vector2
    var time: ContinuousClock.Instant
}
