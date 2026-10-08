import CreatorGeometry

/// One constraint, dimension, implicit condition or drag target, with its operands resolved to
/// unknown columns or constants. Every residual is in millimetres; angle-type residuals are
/// multiplied by the component's length scale so they weigh like millimetres (spec §4).
enum Equation: Hashable, Sendable {
    /// p − q (2 rows).
    case coincident(PointOperand, PointOperand)
    /// Signed distance from p to the infinite line.
    case pointOnLine(PointOperand, LineOperand)
    /// |p − c| − r.
    case pointOnCircle(PointOperand, CircleOperand)
    /// a.y − b.y, for two points.
    case horizontal(PointOperand, PointOperand)
    /// a.x − b.x, for two points.
    case vertical(PointOperand, PointOperand)
    /// scale · d.y / |d|: the sine of the line's angle to the x axis. Angle-based, not a.y − b.y,
    /// so a line can't meet it (and a conflicting angle) by shrinking to nothing.
    case horizontalLine(LineOperand, scale: Double)
    /// scale · d.x / |d|.
    case verticalLine(LineOperand, scale: Double)
    /// scale · sin of the angle between the lines.
    case parallel(LineOperand, LineOperand, scale: Double)
    /// scale · cos of the angle between the lines.
    case perpendicular(LineOperand, LineOperand, scale: Double)
    /// scale · sin(φ − target), φ the signed angle from the first line to the second.
    case angle(LineOperand, LineOperand, target: Double, scale: Double)
    /// Tangency at a shared endpoint p: (p − centre) · direction / |direction| (radius ⟂ line).
    case tangentAtPoint(PointOperand, center: PointOperand, LineOperand)
    /// side · distance(centre, line) − r, for a circle touching a line anywhere.
    case lineTangent(LineOperand, CircleOperand, side: Double)
    /// External: |c₁ − c₂| − (r₁ + r₂). Internal: |c₁ − c₂| − sign · (r₁ − r₂).
    case circleTangent(CircleOperand, CircleOperand, isInternal: Bool, sign: Double)
    /// |d₁| − |d₂|.
    case equalLength(LineOperand, LineOperand)
    /// r₁ − r₂.
    case equalRadius(CircleOperand, CircleOperand)
    /// p − (a + b) / 2 (2 rows).
    case midpoint(PointOperand, LineOperand)
    /// The midpoint of p, q on the line, and q − p along the line is zero (2 rows).
    case symmetric(PointOperand, PointOperand, LineOperand)
    /// p − target (2 rows).
    case fix(PointOperand, Vector2)
    /// |p − q| − d.
    case distance(PointOperand, PointOperand, Double)
    /// side · distance(p, line) − d.
    case lineDistance(PointOperand, LineOperand, Double, side: Double)
    /// |b − a| − L.
    case length(LineOperand, Double)
    /// r − value.
    case radius(CircleOperand, Double)
    /// The implicit arc condition |end − centre| − |start − centre|.
    case arcRadius(center: PointOperand, start: PointOperand, end: PointOperand)
    /// A drag target: p − target (2 rows), used only in drag mode's first phase.
    case target(PointOperand, Vector2)

    var rowCount: Int {
        switch self {
        case .coincident, .midpoint, .symmetric, .fix, .target: 2
        default: 1
        }
    }
}
