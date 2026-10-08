/// Where a world point lands in the viewport, and its depth (0 at the near plane, 1 at the far one).
struct ProjectedPoint: Hashable, Sendable {
    var point: ScreenPoint
    var depth: Double
}
