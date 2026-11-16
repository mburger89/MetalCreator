import CreatorGeometry

/// A cubic Bézier as one degree-5 spline, by exact degree elevation (cubic to quartic to quintic).
enum BezierElevation {
    static func quintic(_ p0: Vector2, _ p1: Vector2, _ p2: Vector2, _ p3: Vector2) -> SplineCurve2D {
        let cubic = [p0, p1, p2, p3]
        let quartic = elevate(cubic)
        let quintic = elevate(quartic)
        return SplineCurve2D(poles: quintic, knots: [0, 1], multiplicities: [6, 6])
    }

    /// The control points of the same curve one degree higher.
    private static func elevate(_ poles: [Vector2]) -> [Vector2] {
        let degree = poles.count - 1
        var result = [poles[0]]
        for index in 1...degree {
            let weight = Double(index) / Double(degree + 1)
            result.append(poles[index - 1] * weight + poles[index] * (1 - weight))
        }
        result.append(poles[degree])
        return result
    }
}
