import CreatorGeometry

/// A line inside an equation: its two endpoints (the line is taken as infinite).
struct LineOperand: Hashable, Sendable {
    var start: PointOperand
    var end: PointOperand

    func direction(_ x: [Double]) -> Vector2 { end.value(x) - start.value(x) }
}
