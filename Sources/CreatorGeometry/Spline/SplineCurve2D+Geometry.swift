import Foundation

extension SplineCurve2D {
    /// The point at parameter `u`, clamped to `parameterRange`.
    public func point(at u: Double) -> Vector2 {
        data.point(at: clamped(u))
    }

    /// The `order`th derivative with respect to the parameter (order 0 is the point). At a knot of multiplicity 3 the
    /// derivatives of order 3 and up are the right-hand span's.
    public func derivative(at u: Double, order: Int) -> Vector2 {
        guard order > 0 else { return point(at: u) }
        guard order <= Self.degree else { return .zero }
        var curve = data
        for _ in 0..<order { curve = curve.derivative }
        return curve.point(at: clamped(u))
    }

    /// Signed curvature, `(C′ × C″) / |C′|³`; 0 where the curve has no tangent.
    public func curvature(at u: Double) -> Double {
        let first = data.derivative
        let (d1, d2) = (first.point(at: clamped(u)), first.derivative.point(at: clamped(u)))
        let speed = d1.length
        guard speed > 0 else { return 0 }
        return (d1.x * d2.y - d1.y * d2.x) / (speed * speed * speed)
    }

    /// Arc length, by 16-point Gauss–Legendre on each knot interval (relative error far below 1e-9 for a span the length of its
    /// chord).
    public var length: Double {
        let speed = data.derivative
        var total = 0.0
        for (a, b) in zip(knots, knots.dropFirst()) {
            let (mid, half) = ((a + b) / 2, (b - a) / 2)
            for (node, weight) in GaussLegendre.sixteen {
                total += weight * half * speed.point(at: mid + half * node).length
            }
        }
        return total
    }

    /// The curve as a polyline: `samplesPerSpan` steps in each knot interval, both ends included.
    public func polyline() -> [Vector2] {
        var points = [startPoint]
        let curve = data
        for (a, b) in zip(knots, knots.dropFirst()) {
            for step in 1...Self.samplesPerSpan {
                let fraction = Double(step) / Double(Self.samplesPerSpan)
                points.append(curve.point(at: step == Self.samplesPerSpan ? b : a + (b - a) * fraction))
            }
        }
        return points
    }

    /// The curve moved by `offset`.
    public func translated(by offset: Vector2) -> SplineCurve2D {
        SplineCurve2D(poles: poles.map { $0 + offset }, knots: knots, multiplicities: multiplicities)
    }

    /// The curve cut at `u` into two curves, each over its part of the parameter range (neither is reparametrized). `nil` unless
    /// `u` is strictly inside the range.
    public func split(at u: Double) -> (SplineCurve2D, SplineCurve2D)? {
        let range = parameterRange
        guard u > range.lowerBound, u < range.upperBound else { return nil }
        // A parameter next to a knot is that knot.
        let target = knots.first { abs($0 - u) <= 1e-12 * max(1, abs(u)) } ?? u
        guard target > range.lowerBound, target < range.upperBound else { return nil }
        var curve = data
        var existing = zip(knots, multiplicities).first { $0.0 == target }?.1 ?? 0
        while existing < Self.degree {
            curve = curve.inserting(target)
            existing += 1
        }
        guard let first = curve.knots.firstIndex(of: target) else { return nil }
        let p = Self.degree
        let leftKnots = Array(curve.knots[0..<(first + p)]) + [target]
        let left = Self.collapsed(poles: Array(curve.poles[0..<first]), knots: leftKnots)
        let rightKnots = [target] + Array(curve.knots[first...])
        let right = Self.collapsed(poles: Array(curve.poles[(first - 1)...]), knots: rightKnots)
        return (left, right)
    }

    private static func collapsed(poles: [Vector2], knots expanded: [Double]) -> SplineCurve2D {
        var knots: [Double] = []
        var multiplicities: [Int] = []
        for knot in expanded {
            if knots.last == knot { multiplicities[multiplicities.count - 1] += 1 } else {
                knots.append(knot)
                multiplicities.append(1)
            }
        }
        return SplineCurve2D(poles: poles, knots: knots, multiplicities: multiplicities)
    }

    /// The parameter of the point on the curve nearest `point`: a sampled start, then Newton's method on the distance's
    /// stationary condition, every local minimum of the samples refined and the best kept.
    public func nearestParameter(to point: Vector2) -> Double {
        let curve = data
        let first = curve.derivative
        let second = first.derivative
        var samples: [(u: Double, distance: Double)] = []
        for (a, b) in zip(knots, knots.dropFirst()) {
            for step in 0..<Self.samplesPerSpan {
                let u = a + (b - a) * Double(step) / Double(Self.samplesPerSpan)
                samples.append((u, (curve.point(at: u) - point).length))
            }
        }
        let end = parameterRange.upperBound
        samples.append((end, (curve.point(at: end) - point).length))
        var best = samples[0].u
        var bestDistance = samples[0].distance
        for index in samples.indices {
            let before = index > 0 ? samples[index - 1].distance : .infinity
            let after = index < samples.count - 1 ? samples[index + 1].distance : .infinity
            guard samples[index].distance <= before, samples[index].distance <= after else { continue }
            let low = samples[max(0, index - 1)].u
            let high = samples[min(samples.count - 1, index + 1)].u
            var u = samples[index].u
            for _ in 0..<30 {
                let c = curve.point(at: u) - point
                let (d1, d2) = (first.point(at: u), second.point(at: u))
                let slope = c.x * d1.x + c.y * d1.y
                let bend = d1.x * d1.x + d1.y * d1.y + c.x * d2.x + c.y * d2.y
                guard bend > 1e-14 else { break }
                let next = min(high, max(low, u - slope / bend))
                if abs(next - u) <= 1e-15 * max(1, abs(u)) {
                    u = next
                    break
                }
                u = next
            }
            let distance = (curve.point(at: u) - point).length
            if distance < bestDistance {
                best = u
                bestDistance = distance
            }
        }
        return best
    }

    private func clamped(_ u: Double) -> Double {
        min(max(u, parameterRange.lowerBound), parameterRange.upperBound)
    }
}

/// Gauss–Legendre nodes and weights, found once by Newton's method on the Legendre polynomial.
enum GaussLegendre {
    static let sixteen: [(node: Double, weight: Double)] = rule(count: 16)

    private static func rule(count n: Int) -> [(node: Double, weight: Double)] {
        (0..<n).map { index in
            var x = cos(Double.pi * (Double(index) + 0.75) / (Double(n) + 0.5))
            var derivative = 1.0
            for _ in 0..<100 {
                var (p0, p1) = (1.0, x)
                for k in 2...n {
                    (p0, p1) = (p1, (Double(2 * k - 1) * x * p1 - Double(k - 1) * p0) / Double(k))
                }
                derivative = Double(n) * (x * p1 - p0) / (x * x - 1)
                let step = p1 / derivative
                x -= step
                if abs(step) < 1e-16 { break }
            }
            return (x, 2 / ((1 - x * x) * derivative * derivative))
        }
    }
}

extension SplineCurve2D {
    /// The same curve walked the other way: poles reversed, knots mirrored in the parameter range.
    public func reversed() -> SplineCurve2D {
        let range = parameterRange
        let sum = range.lowerBound + range.upperBound
        return SplineCurve2D(poles: poles.reversed(), knots: knots.reversed().map { sum - $0 }, multiplicities: multiplicities.reversed())
    }
}
