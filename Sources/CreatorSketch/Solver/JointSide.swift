import CreatorGeometry

/// One curve at a joint it shares with another, seen walking away from the joint: its direction and its signed curvature
/// (positive when it turns counter-clockwise). Two curves meet with equal curvature (G2) when their outgoing directions are
/// opposite and their outgoing curvatures add to zero, or, on the folded branch, when the directions agree and the
/// curvatures are equal (`Equation.jointCurvature`'s `branch`).
enum JointSide: Hashable, Sendable {
    /// A line leaving the joint `from` towards `to`. Curvature 0.
    case line(from: PointOperand, to: PointOperand)
    /// An arc at its start (`sense` +1: it leaves counter-clockwise, curvature +1/r) or at its end (−1: clockwise, −1/r).
    case arc(joint: PointOperand, circle: CircleOperand, sense: Double)
    /// A spline end whose handles are the unknowns at `tangent` and `curvature` (x at the column, y at the next).
    /// `reversed` for the last fit point, where walking away from the joint runs against the spline's parameter.
    case spline(tangent: Int, curvature: Int?, reversed: Bool)

    /// The direction leaving the joint (not normalised).
    func direction(_ x: [Double]) -> Vector2 {
        switch self {
        case .line(let from, let to):
            return to.value(x) - from.value(x)
        case .arc(let joint, let circle, let sense):
            let radial = joint.value(x) - circle.center.value(x)
            return Vector2(-radial.y, radial.x) * sense
        case .spline(let tangent, _, let reversed):
            let value = Vector2(x[tangent], x[tangent + 1])
            return reversed ? value * -1 : value
        }
    }

    /// Adds the gradient `g` with respect to `direction` to `row`, through the columns it depends on.
    func addDirectionGradient(_ g: Vector2, to row: inout RowBuilder) {
        switch self {
        case .line(let from, let to):
            row.add(to, g)
            row.add(from, g * -1)
        case .arc(let joint, let circle, let sense):
            // direction = sense · (−radial.y, radial.x), radial = joint − centre.
            let byRadial = Vector2(g.y, -g.x) * sense
            row.add(joint, byRadial)
            row.add(circle.center, byRadial * -1)
        case .spline(let tangent, _, let reversed):
            let sign = reversed ? -1.0 : 1.0
            row.add(column: tangent, g.x * sign)
            row.add(column: tangent + 1, g.y * sign)
        }
    }

    /// The signed curvature walking away from the joint, with its gradient.
    func curvature(_ x: [Double]) -> RowBuilder {
        switch self {
        case .line:
            return RowBuilder(value: 0)
        case .arc(_, let circle, let sense):
            let radius = circle.radiusValue(x)
            guard radius > 0 else { return RowBuilder(value: 0) }
            var row = RowBuilder(value: sense / radius)
            circle.addRadiusGradient(-sense / (radius * radius), x, to: &row)
            return row
        case .spline(let tangent, let curvature, let reversed):
            guard let curvature else { return RowBuilder(value: 0) }
            let (t, a) = (Vector2(x[tangent], x[tangent + 1]), Vector2(x[curvature], x[curvature + 1]))
            let speed = t.length
            guard speed > 0 else { return RowBuilder(value: 0) }
            // κ = (T × A) / |T|³ along the parameter; walking the other way flips its sign.
            let cube = speed * speed * speed
            let cross = SketchMath.cross(t, a)
            let sign = reversed ? -1.0 : 1.0
            var row = RowBuilder(value: sign * cross / cube)
            let byT = Vector2(a.y, -a.x) * (1 / cube) - t * (3 * cross / (cube * speed * speed))
            let byA = Vector2(-t.y, t.x) * (1 / cube)
            row.add(column: tangent, sign * byT.x)
            row.add(column: tangent + 1, sign * byT.y)
            row.add(column: curvature, sign * byA.x)
            row.add(column: curvature + 1, sign * byA.y)
            return row
        }
    }

    /// Every global column this side reads.
    var columns: [Int] {
        switch self {
        case .line(let from, let to): Equation.columns(from) + Equation.columns(to)
        case .arc(let joint, let circle, _): Equation.columns(joint) + Equation.columns(circle)
        case .spline(let tangent, let curvature, _):
            [tangent, tangent + 1] + (curvature.map { [$0, $0 + 1] } ?? [])
        }
    }
}
