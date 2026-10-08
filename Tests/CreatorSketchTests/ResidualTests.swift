import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Residual values at hand-checked configurations, and every analytic Jacobian against central
/// differences (the solver itself never uses finite differences).
struct ResidualTests {
    // Unknowns: p0 = (1, 2), p1 = (7, 3), p2 = (4, 8), p3 = (−2, 5), r = 2.5.
    static let x: [Double] = [1, 2, 7, 3, 4, 8, -2, 5, 2.5]
    static let p0 = PointOperand.unknown(column: 0)
    static let p1 = PointOperand.unknown(column: 2)
    static let p2 = PointOperand.unknown(column: 4)
    static let p3 = PointOperand.unknown(column: 6)
    static let lineA = LineOperand(start: p0, end: p1)
    static let lineB = LineOperand(start: p2, end: p3)
    static let circle = CircleOperand(center: p2, radius: .unknown(column: 8), endpoints: [])
    static let arc = CircleOperand(center: p0, radius: .through(p3), endpoints: [p3, p1])

    static let equations: [Equation] = [
        .coincident(p0, p1), .pointOnLine(p2, lineA), .pointOnCircle(p1, circle), .pointOnCircle(p1, arc),
        .horizontal(p0, p1), .vertical(p2, p3), .horizontalLine(lineA, scale: 3), .verticalLine(lineB, scale: 3), .parallel(lineA, lineB, scale: 7), .perpendicular(lineA, lineB, scale: 7),
        .angle(lineA, lineB, target: 0.6, scale: 7), .tangentAtPoint(p1, center: p0, lineB),
        .lineTangent(lineA, circle, side: -1), .circleTangent(circle, arc, isInternal: false, sign: 1),
        .circleTangent(circle, arc, isInternal: true, sign: -1), .equalLength(lineA, lineB), .equalRadius(circle, arc),
        .midpoint(p2, lineA), .symmetric(p2, p3, lineA), .fix(p1, Vector2(1, 1)), .distance(p0, p2, 3),
        .lineDistance(p3, lineA, 2, side: 1), .length(lineB, 4), .radius(arc, 1), .arcRadius(center: p0, start: p3, end: p1),
        .target(p2, Vector2(0, 0)), .pointOnLine(.constant(Vector2(3, 3)), LineOperand(start: p0, end: .constant(Vector2(9, 9)))),
    ]

    @Test(arguments: equations)
    func analyticJacobianMatchesCentralDifferences(_ equation: Equation) {
        let rows = equation.rows(Self.x)
        #expect(rows.count == equation.rowCount)
        let h = 1e-6
        for (index, row) in rows.enumerated() {
            var analytic = Array(repeating: 0.0, count: Self.x.count)
            for entry in row.entries { analytic[entry.column] += entry.value }
            for column in Self.x.indices {
                var plus = Self.x
                var minus = Self.x
                plus[column] += h
                minus[column] -= h
                let numeric = (equation.rows(plus)[index].value - equation.rows(minus)[index].value) / (2 * h)
                #expect(isClose(analytic[column], numeric, tolerance: 1e-6), "row \(index), column \(column)")
            }
        }
    }

    @Test func residualValuesMatchHandCalculations() {
        let x = Self.x
        // p2 = (4, 8) from the line (1,2)→(7,3): cross((6,1), (3,6)) / √37 = 33 / √37.
        #expect(isClose(Equation.pointOnLine(Self.p2, Self.lineA).rows(x)[0].value, 33 / 37.0.squareRoot(), tolerance: 1e-12))
        // |p1 − p2| − r = |(3, −5)| − 2.5.
        #expect(isClose(Equation.pointOnCircle(Self.p1, Self.circle).rows(x)[0].value, 34.0.squareRoot() - 2.5, tolerance: 1e-12))
        // Arc radius through p3 around p0: |(−3, 3)| = 3√2.
        #expect(isClose(Equation.radius(Self.arc, 1).rows(x)[0].value, 3 * 2.0.squareRoot() - 1, tolerance: 1e-12))
        #expect(Equation.horizontal(Self.p0, Self.p1).rows(x)[0].value == -1)
        #expect(Equation.vertical(Self.p2, Self.p3).rows(x)[0].value == 6)
        #expect(Equation.midpoint(Self.p2, Self.lineA).rows(x).map(\.value) == [0, 5.5])
        #expect(Equation.fix(Self.p1, Vector2(1, 1)).rows(x).map(\.value) == [6, 2])
    }

    @Test func parallelAndPerpendicularResidualsAreScaledSineAndCosine() {
        let x: [Double] = [0, 0, 10, 0, 0, 5, 10, 15]
        let first = LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))
        let second = LineOperand(start: .unknown(column: 4), end: .unknown(column: 6))
        // The second line is at 45°.
        #expect(isClose(Equation.parallel(first, second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.perpendicular(first, second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.angle(first, second, target: .pi / 4, scale: 10).rows(x)[0].value, 0, tolerance: 1e-12))
        #expect(isClose(Equation.horizontalLine(second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.verticalLine(first, scale: 10).rows(x)[0].value, 10, tolerance: 1e-12))
    }

    @Test func zeroLengthLinesNeverLookSatisfied() {
        let x: [Double] = [3, 3, 3, 3, 0, 0, 10, 0]
        let collapsed = LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))
        let other = LineOperand(start: .unknown(column: 4), end: .unknown(column: 6))
        #expect(Equation.horizontalLine(collapsed, scale: 5).rows(x)[0].value == 5)
        #expect(Equation.parallel(collapsed, other, scale: 5).rows(x)[0].value == 5)
        // A point's distance to a collapsed line is its distance to the point the line became.
        #expect(Equation.pointOnLine(.unknown(column: 4), collapsed).rows(x)[0].value == 18.0.squareRoot())
        // Angle: cos(t) - sin(t) is 0 at 45 degrees, which must not read as satisfied.
        #expect(Equation.angle(collapsed, other, target: .pi / 4, scale: 5).rows(x)[0].value == 5)
        #expect(Equation.angle(other, collapsed, target: 5 * .pi / 4, scale: 5).rows(x)[0].value == 5)
        #expect(Equation.perpendicular(collapsed, other, scale: 5).rows(x)[0].value == 5)
        // Tangent-at-point and symmetric have no length to project along.
        let tangent = Equation.tangentAtPoint(.unknown(column: 4), center: .unknown(column: 6), collapsed)
        #expect(tangent.rows(x)[0].value == 1)
        let symmetric = Equation.symmetric(.unknown(column: 4), .unknown(column: 6), collapsed).rows(x)
        // Midpoint (5, 0) is sqrt(4 + 9) from the collapsed line's point (3, 3).
        #expect(isClose(symmetric[0].value, 13.0.squareRoot(), tolerance: 1e-12))
        #expect(symmetric[1].value == 1)
    }
}
