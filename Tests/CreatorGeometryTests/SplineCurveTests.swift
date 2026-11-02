import Foundation
import Testing
@testable import CreatorGeometry

/// The degree-5 fit-point spline (sketch splines spec, "The curve").
struct SplineCurveTests {
    static let wavy = SplineDefinition(points: [Vector2(0, 0), Vector2(3, 2), Vector2(7, 1), Vector2(10, 4), Vector2(14, 3)])

    private static func close(_ a: Vector2, _ b: Vector2, _ tolerance: Double) -> Bool { (a - b).length <= tolerance }

    private static func deCasteljau(_ poles: [Vector2], _ t: Double) -> Vector2 {
        var level = poles
        while level.count > 1 { level = zip(level, level.dropFirst()).map { $0 * (1 - t) + $1 * t } }
        return level[0]
    }

    /// The Hermite span `i` of a definition, with its resolved data.
    private static func hermite(_ definition: SplineDefinition, _ i: Int) -> QuinticHermite {
        let r = definition.resolvedHandles()
        return QuinticHermite(p0: definition.points[i], p1: definition.points[i + 1], t0: r[i].tangent, t1: r[i + 1].tangent,
                              a0: r[i].secondDerivative, a1: r[i + 1].secondDerivative, h: definition.spans[i])
    }

    private static func value(_ derivative: QuinticHermite.Derivative, _ s: QuinticHermite) -> Vector2 {
        let c = QuinticHermite.coefficients(of: derivative, h: s.h)
        let data = [s.p0, s.p1, s.t0, s.t1, s.a0, s.a1]
        return zip(c, data).reduce(Vector2.zero) { $0 + $1.1 * $1.0 }
    }

    @Test func hermiteToBSplineIsExact() {
        var definition = Self.wavy
        definition.handles[1].tangent = Vector2(0.9, 0.2)
        definition.handles[2].curvature = Vector2(0.05, -0.1)
        let curve = definition.curve()
        #expect(curve.isValid)
        let knots = curve.knots
        for i in 0..<(definition.points.count - 1) {
            let span = Self.hermite(definition, i)
            let bezier = span.bezier
            for step in 0...1000 {
                let t = Double(step) / 1000
                let expected = Self.deCasteljau(bezier, t)
                #expect(Self.close(curve.point(at: knots[i] + span.h * t), expected, 1e-12))
            }
        }
    }

    @Test func fitPointsCarryTheirHandles() {
        var definition = Self.wavy
        definition.handles[2].tangent = Vector2(1, -0.3)
        let curve = definition.curve()
        let resolved = definition.resolvedHandles()
        for (i, u) in curve.knots.enumerated() {
            #expect(Self.close(curve.point(at: u), definition.points[i], 1e-12))
            #expect(Self.close(curve.derivative(at: u, order: 1), resolved[i].tangent, 1e-10))
            #expect(Self.close(curve.derivative(at: u, order: 2), resolved[i].secondDerivative, 1e-9))
        }
        #expect(resolved[2].tangent == Vector2(1, -0.3))
    }

    @Test func chainIsC2() {
        let curve = Self.wavy.curve()
        for knot in curve.knots.dropFirst().dropLast() {
            for order in 0...2 {
                let before = curve.derivative(at: knot - 1e-9, order: order)
                let after = curve.derivative(at: knot + 1e-9, order: order)
                #expect(Self.close(before, after, 1e-6))
            }
        }
        #expect(curve.multiplicities == [6, 3, 3, 3, 6])
    }

    @Test func automaticHandlesMakeTheThirdAndFourthDerivativesContinuous() {
        let d = Self.wavy
        let spans = (0..<(d.points.count - 1)).map { Self.hermite(d, $0) }
        for i in 1..<(d.points.count - 1) {
            #expect(Self.close(Self.value(.thirdAtEnd, spans[i - 1]), Self.value(.thirdAtStart, spans[i]), 1e-9))
            #expect(Self.close(Self.value(.fourthAtEnd, spans[i - 1]), Self.value(.fourthAtStart, spans[i]), 1e-8))
        }
        #expect(Self.value(.thirdAtStart, spans[0]).length < 1e-9)
        #expect(Self.value(.fourthAtStart, spans[0]).length < 1e-8)
        #expect(Self.value(.thirdAtEnd, spans[spans.count - 1]).length < 1e-9)
        #expect(Self.value(.fourthAtEnd, spans[spans.count - 1]).length < 1e-8)
    }

    @Test func derivativeFunctionalsMatchTheCurve() {
        // The functionals the solve is built from give the Bézier curve's own higher derivatives.
        let span = Self.hermite(Self.wavy, 1)
        let curve = SplineCurve2D(poles: span.bezier, knots: [0, span.h], multiplicities: [6, 6])
        #expect(Self.close(Self.value(.thirdAtStart, span), curve.derivative(at: 0, order: 3), 1e-9))
        #expect(Self.close(Self.value(.thirdAtEnd, span), curve.derivative(at: span.h, order: 3), 1e-9))
        #expect(Self.close(Self.value(.fourthAtStart, span), curve.derivative(at: 0, order: 4), 1e-8))
        #expect(Self.close(Self.value(.fourthAtEnd, span), curve.derivative(at: span.h, order: 4), 1e-8))
    }

    @Test func unevenPointsOnALineStayOnTheLine() {
        // The chord parameter is then x itself, so the automatic handles are T = (1, 0) and A = 0 exactly.
        let d = SplineDefinition(points: [0, 1, 4, 5, 9, 10.5].map { Vector2($0, 0) })
        for handle in d.resolvedHandles() {
            #expect(Self.close(handle.tangent, Vector2(1, 0), 1e-9))
            #expect(handle.secondDerivative.length < 1e-9)
        }
    }

    @Test func automaticHandlesFollowAQuinticAwayFromTheEnds() {
        // Fit points on y = x^5 - 2x^3 + x; the chord parameter is not x, so this is close rather than exact.
        let points = (-12...12).map { Double($0) / 10 }.map { Vector2($0, pow($0, 5) - 2 * pow($0, 3) + $0) }
        let curve = SplineDefinition(points: points).curve()
        var worst = 0.0
        let range = curve.parameterRange
        for step in 0...2000 {
            let u = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 2000
            let p = curve.point(at: u)
            guard abs(p.x) < 0.7 else { continue }
            worst = max(worst, abs(p.y - (pow(p.x, 5) - 2 * pow(p.x, 3) + p.x)))
        }
        #expect(worst < 1e-4)
    }

    @Test func twoPointSplineIsTheChord() {
        let d = SplineDefinition(points: [Vector2(1, 2), Vector2(7, 10)])
        let curve = d.curve()
        #expect(curve.poles.count == 6)
        for step in 0...20 {
            let u = curve.parameterRange.upperBound * Double(step) / 20
            let expected = Vector2(1, 2) + (Vector2(6, 8)) * (u / 10)
            #expect(Self.close(curve.point(at: u), expected, 1e-12))
        }
        #expect(abs(curve.length - 10) < 1e-12)
        #expect(abs(curve.curvature(at: 5)) < 1e-12)
    }

    @Test func curvatureMatchesFiniteDifferences() {
        let curve = Self.wavy.curve()
        let range = curve.parameterRange
        let e = 1e-4
        for step in 1..<40 {
            let u = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 40
            let (a, b, c) = (curve.point(at: u - e), curve.point(at: u), curve.point(at: u + e))
            let d1 = (c - a) * (1 / (2 * e))
            let d2 = (a - b * 2 + c) * (1 / (e * e))
            let expected = (d1.x * d2.y - d1.y * d2.x) / pow(d1.length, 3)
            #expect(abs(curve.curvature(at: u) - expected) < 1e-4)
        }
        let resolved = Self.wavy.resolvedHandles()
        for (i, u) in curve.knots.enumerated() {
            #expect(abs(resolved[i].curvature - curve.curvature(at: u)) < 1e-9)
        }
    }

    @Test func oneActiveHandleKeepsTheLowerCondition() {
        var d = Self.wavy
        d.handles[2].curvature = Vector2(0.4, -0.2)
        let r = d.resolvedHandles()
        #expect(r[2].secondDerivative == Vector2(0.4, -0.2))
        let spans = (0..<(d.points.count - 1)).map { Self.hermite(d, $0) }
        // The third derivative joins at point 2 ...
        #expect(Self.close(Self.value(.thirdAtEnd, spans[1]), Self.value(.thirdAtStart, spans[2]), 1e-9))
        // ... the fourth has no unknown left to spend on it.
        #expect(!Self.close(Self.value(.fourthAtEnd, spans[1]), Self.value(.fourthAtStart, spans[2]), 1e-6))
        // The other points still join in both.
        #expect(Self.close(Self.value(.fourthAtEnd, spans[0]), Self.value(.fourthAtStart, spans[1]), 1e-8))
        // An end with one active handle keeps only the third derivative zero.
        d.handles[0].tangent = Vector2(1, 0.5)
        let spansAfter = (0..<(d.points.count - 1)).map { Self.hermite(d, $0) }
        #expect(Self.value(.thirdAtStart, spansAfter[0]).length < 1e-9)
    }

    @Test func lengthAndBoundsAndSplit() {
        let curve = Self.wavy.curve()
        var dense = 0.0
        let n = 200_000
        let range = curve.parameterRange
        var last = curve.point(at: range.lowerBound)
        for step in 1...n {
            let p = curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / Double(n))
            dense += (p - last).length
            last = p
        }
        #expect(abs(curve.length - dense) / dense < 1e-8)

        let segment = Segment2D.spline(curve)
        let box = segment.boundingPoints
        let (minX, maxX) = (box.map(\.x).min()!, box.map(\.x).max()!)
        let (minY, maxY) = (box.map(\.y).min()!, box.map(\.y).max()!)
        for p in curve.polyline() {
            #expect(p.x >= minX - 1e-12 && p.x <= maxX + 1e-12 && p.y >= minY - 1e-12 && p.y <= maxY + 1e-12)
        }

        for u in [2.0, curve.knots[2], 12.34] {
            let (left, right) = curve.split(at: u)!
            #expect(left.isValid && right.isValid)
            #expect(left.parameterRange == range.lowerBound...u && right.parameterRange == u...range.upperBound)
            #expect(abs(left.length + right.length - curve.length) < 1e-9)
            #expect(Self.close(left.endPoint, curve.point(at: u), 1e-12) && Self.close(right.startPoint, curve.point(at: u), 1e-12))
            for step in 0...50 {
                let a = left.parameterRange.lowerBound + (u - left.parameterRange.lowerBound) * Double(step) / 50
                #expect(Self.close(left.point(at: a), curve.point(at: a), 1e-11))
                let b = u + (right.parameterRange.upperBound - u) * Double(step) / 50
                #expect(Self.close(right.point(at: b), curve.point(at: b), 1e-11))
            }
        }
        #expect(curve.split(at: range.lowerBound) == nil)
        #expect(curve.split(at: range.upperBound + 1) == nil)
    }

    @Test func nearestPoint() {
        let curve = Self.wavy.curve()
        let range = curve.parameterRange
        for step in 0...30 {
            let u = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 30
            let tangent = curve.derivative(at: u, order: 1)
            let normal = Vector2(-tangent.y, tangent.x) * (0.7 / tangent.length)
            let probe = curve.point(at: u) + normal
            let found = curve.nearestParameter(to: probe)
            var brute = Double.infinity
            for k in 0...20_000 {
                let p = curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double(k) / 20_000)
                brute = min(brute, (p - probe).length)
            }
            #expect((curve.point(at: found) - probe).length <= brute + 1e-9)
        }
        // Beyond an end it is the end.
        #expect(curve.nearestParameter(to: Vector2(-50, -50)) == range.lowerBound)
    }

    @Test func aSplineSegmentBehavesAsASegment() {
        let curve = Self.wavy.curve()
        let segment = Segment2D.spline(curve)
        #expect(segment.startPoint == curve.startPoint && segment.endPoint == curve.endPoint)
        #expect(segment.startPoint == Vector2(0, 0) && segment.endPoint == Vector2(14, 3))
        #expect(abs(segment.length - curve.length) < 1e-12)
        #expect(segment.isSpline)
        let moved = segment.translated(by: Vector2(5, -1))
        #expect(moved.startPoint == Vector2(5, -1) && Self.close(moved.endPoint, Vector2(19, 2), 1e-12))
    }

    @Test func aProfileWithASplineIsCountedContainedAndMeasured() {
        let curve = SplineDefinition(points: [Vector2(0, 0), Vector2(5, 3), Vector2(10, 0)]).curve()
        let profile = Profile2D(plane: .xy, segments: [.spline(curve), .line(Vector2(10, 0), Vector2(0, 0))])
        #expect(profile.hasSpline && profile.isClosed)
        #expect(profile.contains(Vector2(5, 1)))
        #expect(!profile.contains(Vector2(5, 4)))
        #expect(!profile.contains(Vector2(5, -1)))
        #expect(!Profile2D.rectangle(width: 2, height: 2, plane: .xy).hasSpline)
        let distance = ProfileDistance(profile)
        #expect(abs(distance.distance(from: Vector3(5, -2, 0)) - 2) < 1e-9)
        let top = curve.point(at: curve.nearestParameter(to: Vector2(5, 10)))
        #expect(abs(distance.distance(from: Vector3(5, 10, 0)) - (Vector2(5, 10) - top).length) < 1e-9)
        let flat = distance.distance(from: Vector3(5, 1, 0))
        #expect(abs(distance.distance(from: Vector3(5, 1, 3)) - (flat * flat + 9).squareRoot()) < 1e-9)
    }
}
