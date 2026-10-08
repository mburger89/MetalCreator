import CreatorGeometry

/// An arc or circle inside an equation (arcs count as their full circle).
struct CircleOperand: Hashable, Sendable {
    var center: PointOperand
    var radius: RadiusOperand
    /// The arc's start and end points, `nil` for circles and projected curves. Used to detect
    /// tangency at a shared endpoint.
    var endpoints: [PointOperand]

    func radiusValue(_ x: [Double]) -> Double {
        switch radius {
        case .unknown(let column): x[column]
        case .constant(let value): value
        case .through(let point): (point.value(x) - center.value(x)).length
        }
    }

    /// Adds `scale · ∂radius/∂x` to `row`.
    func addRadiusGradient(_ scale: Double, _ x: [Double], to row: inout RowBuilder) {
        switch radius {
        case .unknown(let column): row.add(column: column, scale)
        case .constant: break
        case .through(let point):
            let offset = point.value(x) - center.value(x)
            let length = offset.length
            guard length > 0 else { return }
            let unit = offset * (scale / length)
            row.add(point, unit)
            row.add(center, unit * -1)
        }
    }
}
