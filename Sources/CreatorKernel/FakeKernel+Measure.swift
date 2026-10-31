import CreatorGeometry

extension FakeKernel {
    public func shortestDistance(between first: MeasureElement, and second: MeasureElement) throws -> ShapeDistance {
        try Task.checkCancellation()
        let a = try Self.measurable(first), b = try Self.measurable(second)
        switch (a, b) {
        case (.point(let p), .point(let q)):
            return ShapeDistance(distance: (p - q).length, from: p, to: q)
        case (.point(let p), .segment(let start, let end)):
            let q = Self.closest(on: start, end, to: p)
            return ShapeDistance(distance: (p - q).length, from: p, to: q)
        case (.segment(let start, let end), .point(let q)):
            let p = Self.closest(on: start, end, to: q)
            return ShapeDistance(distance: (p - q).length, from: p, to: q)
        case (.segment(let a0, let a1), .segment(let b0, let b1)):
            let (p, q) = Self.closestPoints(a0, a1, b0, b1)
            return ShapeDistance(distance: (p - q).length, from: p, to: q)
        }
    }

    private enum Measurable {
        case point(Vector3)
        case segment(Vector3, Vector3)
    }

    private static func measurable(_ element: MeasureElement) throws -> Measurable {
        switch element {
        case .point(let point):
            guard point.isFinite else { throw KernelError.invalidInput("That point is not finite.") }
            return .point(point)
        case .face(let solid, let id):
            guard solid.topology.face(id) != nil else { throw KernelError.invalidInput("That face or edge no longer exists.") }
            throw KernelError.unsupported("measuring a face")
        case .edge(let solid, let id):
            guard let edge = solid.topology.edge(id) else { throw KernelError.invalidInput("That face or edge no longer exists.") }
            guard case .line(let start, let end)? = edge.curve else { throw KernelError.unsupported("measuring a curved edge") }
            return .segment(start, end)
        }
    }

    private static func closest(on start: Vector3, _ end: Vector3, to point: Vector3) -> Vector3 {
        let d = end - start
        let lengthSquared = d.dot(d)
        guard lengthSquared > 0 else { return start }
        let t = min(max((point - start).dot(d) / lengthSquared, 0), 1)
        return start + d * t
    }

    /// The closest points of two segments (Ericson, Real-Time Collision Detection 5.1.9).
    private static func closestPoints(_ p1: Vector3, _ q1: Vector3, _ p2: Vector3, _ q2: Vector3) -> (Vector3, Vector3) {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r)
        let epsilon = 1e-12
        var s = 0.0, t = 0.0
        if a <= epsilon && e <= epsilon {
            return (p1, p2)
        } else if a <= epsilon {
            t = min(max(f / e, 0), 1)
        } else {
            let c = d1.dot(r)
            if e <= epsilon {
                s = min(max(-c / a, 0), 1)
            } else {
                let b = d1.dot(d2)
                let denominator = a * e - b * b
                s = denominator > epsilon ? min(max((b * f - c * e) / denominator, 0), 1) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = min(max(-c / a, 0), 1)
                } else if t > 1 {
                    t = 1
                    s = min(max((b - c) / a, 0), 1)
                }
            }
        }
        return (p1 + d1 * s, p2 + d2 * t)
    }
}
